#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_DIR="$ROOT/.vps-runtime"
BACKUP_DIR="$RUNTIME_DIR/backups"
POLICY_FILE="$RUNTIME_DIR/backup-retention.env"
OFFSITE_CONFIG="$RUNTIME_DIR/offsite.env"
MODE="dry-run"
OFFSITE_READY=0

usage() {
  echo "Usage: $0 [--dry-run|--apply]" >&2
  exit 2
}
case "${1:---dry-run}" in
  --dry-run) MODE="dry-run"; shift || true ;;
  --apply) MODE="apply"; shift || true ;;
  *) usage ;;
esac
[[ $# -eq 0 ]] || usage
for command in flock realpath stat sha256sum awk sort python3; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

if [[ ! -e "$POLICY_FILE" ]]; then
  printf 'Retention policy is not configured; no files will be deleted.\n'
  [[ "$MODE" == "dry-run" ]] && exit 0
  echo "Cannot apply retention without $POLICY_FILE." >&2
  exit 1
fi
[[ -f "$POLICY_FILE" && ! -L "$POLICY_FILE" ]] || {
  echo "Retention policy must be a regular non-symlink file." >&2
  exit 1
}
[[ "$(stat -c '%a' "$POLICY_FILE")" == "600" ]] || {
  echo "Retention policy must have mode 600." >&2
  exit 1
}
[[ "$(stat -c '%u' "$POLICY_FILE")" == "$(id -u)" ]] || {
  echo "Retention policy must be owned by the account running this script." >&2
  exit 1
}

# This file is an operator-managed shell environment file. It must be owner-controlled.
set -a
# shellcheck source=/dev/null
. "$POLICY_FILE"
set +a

RETENTION_ENABLED="${FLOWLESSHUB_BACKUP_RETENTION_ENABLED:-0}"
KEEP_LAST="${FLOWLESSHUB_BACKUP_RETENTION_KEEP_LAST:-}"
ALLOW_DELETE="${FLOWLESSHUB_BACKUP_RETENTION_ALLOW_DELETE:-0}"

if [[ "$RETENTION_ENABLED" != "1" ]]; then
  printf 'Retention is disabled by policy; no files will be deleted.\n'
  [[ "$MODE" == "dry-run" ]] && exit 0
  echo "Retention apply refused: FLOWLESSHUB_BACKUP_RETENTION_ENABLED is not 1." >&2
  exit 1
fi
[[ "$KEEP_LAST" =~ ^[0-9]+$ ]] || {
  echo "FLOWLESSHUB_BACKUP_RETENTION_KEEP_LAST must be an integer." >&2
  exit 1
}
(( KEEP_LAST >= 2 )) || {
  echo "Retention must preserve at least two newest local backups." >&2
  exit 1
}
if [[ "$MODE" == "apply" && "$ALLOW_DELETE" != "1" ]]; then
  echo "Retention apply refused: FLOWLESSHUB_BACKUP_RETENTION_ALLOW_DELETE must be 1." >&2
  exit 1
fi

# Local deletion requires a live remote snapshot lookup, not merely a local marker.
# The off-site config is owner-controlled and must never be printed or committed.
if [[ -f "$OFFSITE_CONFIG" && ! -L "$OFFSITE_CONFIG" && \
      "$(stat -c '%a' "$OFFSITE_CONFIG")" == "600" && \
      "$(stat -c '%u' "$OFFSITE_CONFIG")" == "$(id -u)" ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$OFFSITE_CONFIG"
  set +a
  if [[ "${FLOWLESSHUB_OFFSITE_ENABLED:-0}" == "1" && \
        "${RESTIC_REPOSITORY:-}" =~ ^s3:https://[^[:space:]]+$ && \
        -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" && \
        -n "${AWS_DEFAULT_REGION:-}" && \
        -n "${RESTIC_PASSWORD_FILE:-}" ]] && \
        command -v restic >/dev/null 2>&1; then
    RUNTIME_DIR_REAL="$(realpath -e -- "$RUNTIME_DIR")"
    if [[ -f "$RESTIC_PASSWORD_FILE" && ! -L "$RESTIC_PASSWORD_FILE" ]]; then
      RESTIC_PASSWORD_REAL="$(realpath -e -- "$RESTIC_PASSWORD_FILE" 2>/dev/null || true)"
      if [[ -n "$RESTIC_PASSWORD_REAL" && \
            "$RESTIC_PASSWORD_REAL" == "$RUNTIME_DIR_REAL/"* && \
            "$(stat -c '%a' "$RESTIC_PASSWORD_REAL")" == "600" && \
            "$(stat -c '%u' "$RESTIC_PASSWORD_REAL")" == "$(id -u)" ]]; then
        RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_REAL"
        export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
        OFFSITE_READY=1
      fi
    fi
  fi
fi

if [[ "$MODE" == "apply" && "$OFFSITE_READY" != "1" ]]; then
  echo "Retention apply refused: live off-site repository verification is unavailable." >&2
  exit 1
fi

BACKUP_DIR_REAL="$(realpath -e -- "$BACKUP_DIR")"
[[ "$BACKUP_DIR_REAL" == "$ROOT/.vps-runtime/backups" ]] || {
  echo "Unexpected backup directory resolution; refusing retention." >&2
  exit 1
}

# Serialize retention with backup, off-site upload, and restore operations.
exec 9>"$RUNTIME_DIR/backup.lock"
flock -n 9 || {
  echo "Another FlowlessHub backup/restore/off-site operation is running." >&2
  exit 1
}

manifest_value() {
  local file="$1" key="$2"
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; found=1; exit} END {if (!found) exit 1}' "$file"
}

marker_value() {
  local file="$1" key="$2"
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; found=1; exit} END {if (!found) exit 1}' "$file"
}

ARCHIVES=()
for archive in "$BACKUP_DIR_REAL"/flowlesshub-*.dump; do
  [[ -e "$archive" || -L "$archive" ]] || continue
  [[ -f "$archive" && ! -L "$archive" ]] || {
    echo "Unexpected non-regular backup entry: $archive" >&2
    exit 1
  }
  base="$(basename "$archive")"
  [[ "$base" =~ ^flowlesshub-[0-9]{8}T[0-9]{6}Z\.dump$ ]] || {
    echo "Unexpected backup filename: $base" >&2
    exit 1
  }
  ARCHIVES+=("$base")
done

if ((${#ARCHIVES[@]} == 0)); then
  printf 'No local FlowlessHub backup archives found.\n'
  exit 0
fi

mapfile -t SORTED_ARCHIVES < <(printf '%s\n' "${ARCHIVES[@]}" | LC_ALL=C sort -r)
DELETE_CANDIDATES=()
printf 'Retention mode: %s; keep newest: %s\n' "$MODE" "$KEEP_LAST"

for index in "${!SORTED_ARCHIVES[@]}"; do
  base="${SORTED_ARCHIVES[$index]}"
  archive="$BACKUP_DIR_REAL/$base"
  sha_file="$archive.sha256"
  manifest_file="$archive.manifest"
  marker_file="$archive.offsite-uploaded"
  for file in "$archive" "$sha_file" "$manifest_file"; do
    [[ -f "$file" && ! -L "$file" ]] || {
      echo "Incomplete or unsafe backup artifact set: $base" >&2
      exit 1
    }
    [[ "$(stat -c '%a' "$file")" == "600" ]] || {
      echo "Backup artifact must have mode 600: $(basename "$file")" >&2
      exit 1
    }
  done
  (
    cd "$BACKUP_DIR_REAL"
    sha256sum --check "$(basename "$sha_file")" >/dev/null
  ) || {
    echo "Checksum verification failed; retention stopped: $base" >&2
    exit 1
  }
  expected_file="$(manifest_value "$manifest_file" backup_file)"
  expected_sha="$(manifest_value "$manifest_file" backup_sha256)"
  sidecar_sha="$(awk '{print $1}' "$sha_file")"
  [[ "$expected_file" == "$base" && "$expected_sha" =~ ^[0-9a-f]{64}$ && "$expected_sha" == "$sidecar_sha" ]] || {
    echo "Manifest/checksum metadata mismatch; retention stopped: $base" >&2
    exit 1
  }

  if (( index < KEEP_LAST )); then
    printf 'KEEP newest: %s\n' "$base"
    continue
  fi

  if [[ ! -f "$marker_file" || -L "$marker_file" ]]; then
    printf 'KEEP without off-site upload marker: %s\n' "$base"
    continue
  fi
  [[ "$(stat -c '%a' "$marker_file")" == "600" ]] || {
    echo "Off-site upload marker must have mode 600: $base" >&2
    exit 1
  }
  marker_file_name="$(marker_value "$marker_file" backup_file)"
  marker_sha="$(marker_value "$marker_file" backup_sha256)"
  marker_snapshot="$(marker_value "$marker_file" restic_snapshot_id)"
  marker_format="$(marker_value "$marker_file" format)"
  marker_archive_sha="$(marker_value "$marker_file" remote_archive_sha256)"
  marker_sidecar_sha="$(marker_value "$marker_file" remote_sha256_sidecar_sha256)"
  marker_manifest_sha="$(marker_value "$marker_file" remote_manifest_sha256)"
  marker_readback_verified="$(marker_value "$marker_file" readback_verified)"
  local_sidecar_sha="$(sha256sum "$sha_file" | awk '{print $1}')"
  local_manifest_sha="$(sha256sum "$manifest_file" | awk '{print $1}')"
  [[ "$marker_format" == "restic-s3-readback-v2" && \
     "$marker_file_name" == "$base" && \
     "$marker_sha" == "$expected_sha" && \
     "$marker_archive_sha" == "$expected_sha" && \
     "$marker_sidecar_sha" == "$local_sidecar_sha" && \
     "$marker_manifest_sha" == "$local_manifest_sha" && \
     "$marker_readback_verified" == "archive-and-sidecars" && \
     "$marker_snapshot" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Off-site upload/read-back marker does not match the local archive triplet: $base" >&2
    exit 1
  }

  if [[ "$OFFSITE_READY" != "1" ]]; then
    printf 'KEEP without live off-site repository verification: %s\n' "$base"
    continue
  fi

  remote_json="$(restic snapshots --json --tag "artifact=$base")" || {
    echo "Remote snapshot lookup failed; retention stopped: $base" >&2
    exit 1
  }
  if ! printf '%s' "$remote_json" | python3 -c '
import json, sys
expected = sys.argv[1]
try:
    snapshots = json.load(sys.stdin)
except Exception:
    raise SystemExit(2)
if not isinstance(snapshots, list):
    raise SystemExit(2)
for snapshot in snapshots:
    if snapshot.get("id") == expected and "flowlesshub" in (snapshot.get("tags") or []):
        raise SystemExit(0)
raise SystemExit(1)
' "$marker_snapshot"; then
    printf 'KEEP: marker snapshot is not present in the remote repository: %s\n' "$base"
    continue
  fi

  if [[ "$MODE" == "apply" ]]; then
    printf 'DELETE CANDIDATE (final live read-back will run immediately before deletion): %s\n' "$base"
  else
    printf 'DRY-RUN CANDIDATE (marker + live snapshot verified; --apply will re-read all bytes): %s\n' "$base"
  fi
  DELETE_CANDIDATES+=("$base")
done

if [[ "$MODE" == "dry-run" ]]; then
  printf 'Dry-run complete. No files were deleted. Eligible groups: %s\n' "${#DELETE_CANDIDATES[@]}"
  exit 0
fi

for base in "${DELETE_CANDIDATES[@]}"; do
  archive="$BACKUP_DIR_REAL/$base"
  sha_file="$archive.sha256"
  manifest_file="$archive.manifest"
  marker_file="$archive.offsite-uploaded"

  # Revalidate every local artifact and its marker after the candidate scan.
  # This is the final gate: no other candidates are processed between the
  # fresh remote read-back and removal of this artifact group.
  for file in "$archive" "$sha_file" "$manifest_file" "$marker_file"; do
    [[ -f "$file" && ! -L "$file" ]] || {
      echo "Final retention check found an incomplete or unsafe artifact: $file" >&2
      exit 1
    }
    [[ "$(stat -c '%a' "$file")" == "600" ]] || {
      echo "Final retention check requires mode 600: $file" >&2
      exit 1
    }
  done

  (
    cd "$BACKUP_DIR_REAL"
    sha256sum --check "$(basename "$sha_file")" >/dev/null
  ) || {
    echo "Final checksum verification failed; retention stopped: $base" >&2
    exit 1
  }

  expected_file="$(manifest_value "$manifest_file" backup_file)"
  expected_sha="$(manifest_value "$manifest_file" backup_sha256)"
  marker_file_name="$(marker_value "$marker_file" backup_file)"
  marker_sha="$(marker_value "$marker_file" backup_sha256)"
  marker_snapshot="$(marker_value "$marker_file" restic_snapshot_id)"
  marker_format="$(marker_value "$marker_file" format)"
  marker_archive_sha="$(marker_value "$marker_file" remote_archive_sha256)"
  marker_sidecar_sha="$(marker_value "$marker_file" remote_sha256_sidecar_sha256)"
  marker_manifest_sha="$(marker_value "$marker_file" remote_manifest_sha256)"
  marker_readback_verified="$(marker_value "$marker_file" readback_verified)"
  local_sidecar_sha="$(sha256sum "$sha_file" | awk '{print $1}')"
  local_manifest_sha="$(sha256sum "$manifest_file" | awk '{print $1}')"
  marker_file_sha="$(sha256sum "$marker_file" | awk '{print $1}')"

  [[ "$expected_file" == "$base" && "$expected_sha" =~ ^[0-9a-f]{64}$ && \
     "$marker_format" == "restic-s3-readback-v2" && \
     "$marker_file_name" == "$base" && \
     "$marker_sha" == "$expected_sha" && \
     "$marker_archive_sha" == "$expected_sha" && \
     "$marker_sidecar_sha" == "$local_sidecar_sha" && \
     "$marker_manifest_sha" == "$local_manifest_sha" && \
     "$marker_readback_verified" == "archive-and-sidecars" && \
     "$marker_snapshot" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Final marker/manifest verification failed; retention stopped: $base" >&2
    exit 1
  }

  # Re-list the exact tagged snapshot, then read all three files from it.
  # The listing alone is not sufficient deletion evidence.
  remote_json="$(restic snapshots --json --tag "artifact=$base")" || {
    echo "Final remote snapshot lookup failed; retention stopped: $base" >&2
    exit 1
  }
  if ! printf '%s' "$remote_json" | python3 -c '
import json, sys
expected = sys.argv[1]
try:
    snapshots = json.load(sys.stdin)
except Exception:
    raise SystemExit(2)
if not isinstance(snapshots, list):
    raise SystemExit(2)
for snapshot in snapshots:
    if snapshot.get("id") == expected and "flowlesshub" in (snapshot.get("tags") or []):
        raise SystemExit(0)
raise SystemExit(1)
' "$marker_snapshot"; then
    echo "Final remote snapshot verification failed; retention stopped: $base" >&2
    exit 1
  fi

  for file in "$archive" "$sha_file" "$manifest_file"; do
    local_file_sha="$(sha256sum "$file" | awk '{print $1}')"
    if ! remote_file_sha="$(restic dump "$marker_snapshot" "$file" | sha256sum | awk '{print $1}')"; then
      echo "Final remote read-back failed; retention stopped: $(basename "$file")" >&2
      exit 1
    fi
    [[ "$remote_file_sha" =~ ^[0-9a-f]{64}$ && "$remote_file_sha" == "$local_file_sha" ]] || {
      echo "Final remote read-back SHA-256 mismatch; retention stopped: $(basename "$file")" >&2
      exit 1
    }
  done

  # Ensure the local set and authorization marker did not change during read-back.
  [[ "$(sha256sum "$archive" | awk '{print $1}')" == "$expected_sha" && \
     "$(sha256sum "$sha_file" | awk '{print $1}')" == "$marker_sidecar_sha" && \
     "$(sha256sum "$manifest_file" | awk '{print $1}')" == "$marker_manifest_sha" && \
     "$(sha256sum "$marker_file" | awk '{print $1}')" == "$marker_file_sha" ]] || {
    echo "Local artifacts or marker changed during final read-back; retention stopped: $base" >&2
    exit 1
  }

  printf 'DELETE local-only copies after final remote read-back: %s\n' "$base"
  rm -- "$archive" "$sha_file" "$manifest_file" "$marker_file"
  deleted_count=$(( ${deleted_count:-0} + 1 ))
done
printf 'Retention apply completed. Deleted artifact groups: %s\n' "${deleted_count:-0}"
printf 'Each deleted artifact group passed final remote archive/sidecar read-back immediately before deletion.\n'
printf 'Off-site repository snapshots were not pruned by this script.\n'
