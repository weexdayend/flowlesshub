#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_DIR="$ROOT/.vps-runtime"
BACKUP_DIR="$RUNTIME_DIR/backups"
CONFIG_FILE="$RUNTIME_DIR/offsite.env"

usage() {
  echo "Usage: $0 <path-to-flowlesshub-backup.dump>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
for command in restic flock realpath stat sha256sum awk date mktemp python3; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

if [[ ! -e "$CONFIG_FILE" ]]; then
  echo "OFFSITE_NOT_CONFIGURED: $CONFIG_FILE is absent; no off-site upload was attempted."
  exit 3
fi
[[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || {
  echo "Off-site config must be a regular non-symlink file." >&2
  exit 1
}
[[ "$(stat -c '%a' "$CONFIG_FILE")" == "600" ]] || {
  echo "Off-site config must have mode 600." >&2
  exit 1
}
[[ "$(stat -c '%u' "$CONFIG_FILE")" == "$(id -u)" ]] || {
  echo "Off-site config must be owned by the account running this script." >&2
  exit 1
}

# This file is an operator-managed shell environment file. It must be owner-controlled.
set -a
# shellcheck source=/dev/null
. "$CONFIG_FILE"
set +a

if [[ "${FLOWLESSHUB_OFFSITE_ENABLED:-0}" != "1" ]]; then
  echo "OFFSITE_DISABLED: off-site upload is not enabled; no upload was attempted."
  exit 3
fi

[[ "${RESTIC_REPOSITORY:-}" =~ ^s3:https://[^[:space:]]+$ ]] || {
  echo "RESTIC_REPOSITORY must be an S3-compatible HTTPS repository URL (s3:https://...)." >&2
  exit 1
}
[[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]] || {
  echo "S3-compatible access credentials are missing from the protected config." >&2
  exit 1
}
[[ -n "${AWS_DEFAULT_REGION:-}" ]] || {
  echo "AWS_DEFAULT_REGION must be explicitly configured." >&2
  exit 1
}
RUNTIME_DIR_REAL="$(realpath -e -- "$RUNTIME_DIR")"
[[ -n "${RESTIC_PASSWORD_FILE:-}" ]] || {
  echo "RESTIC_PASSWORD_FILE must be configured." >&2
  exit 1
}
[[ -f "$RESTIC_PASSWORD_FILE" && ! -L "$RESTIC_PASSWORD_FILE" ]] || {
  echo "Restic password file must exist as a regular non-symlink file." >&2
  exit 1
}
RESTIC_PASSWORD_REAL="$(realpath -e -- "$RESTIC_PASSWORD_FILE")"
[[ "$RESTIC_PASSWORD_REAL" == "$RUNTIME_DIR_REAL/"* ]] || {
  echo "Resolved RESTIC_PASSWORD_FILE must remain inside .vps-runtime." >&2
  exit 1
}
RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_REAL"
[[ "$(stat -c '%a' "$RESTIC_PASSWORD_FILE")" == "600" ]] || {
  echo "Restic password file must have mode 600." >&2
  exit 1
}
[[ "$(stat -c '%u' "$RESTIC_PASSWORD_FILE")" == "$(id -u)" ]] || {
  echo "Restic password file must be owned by the account running this script." >&2
  exit 1
}

BACKUP_DIR_REAL="$(realpath -e -- "$BACKUP_DIR")"
BACKUP_PATH="$(realpath -e -- "$1")"
[[ "$(dirname "$BACKUP_PATH")" == "$BACKUP_DIR_REAL" ]] || {
  echo "Backup must be a direct artifact inside $BACKUP_DIR_REAL." >&2
  exit 1
}
[[ -f "$BACKUP_PATH" && ! -L "$1" ]] || {
  echo "Backup archive must be a regular non-symlink file." >&2
  exit 1
}

BASE="$(basename "$BACKUP_PATH")"
[[ "$BASE" =~ ^flowlesshub-[0-9]{8}T[0-9]{6}Z\.dump$ ]] || {
  echo "Unexpected backup filename: $BASE" >&2
  exit 1
}
SHA_FILE="$BACKUP_PATH.sha256"
MANIFEST_FILE="$BACKUP_PATH.manifest"
for file in "$BACKUP_PATH" "$SHA_FILE" "$MANIFEST_FILE"; do
  [[ -f "$file" && ! -L "$file" ]] || {
    echo "Backup archive and both sidecars must be regular non-symlink files." >&2
    exit 1
  }
  [[ "$(stat -c '%a' "$file")" == "600" ]] || {
    echo "Backup artifact must have mode 600: $(basename "$file")" >&2
    exit 1
  }
done

manifest_value() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; found=1; exit} END {if (!found) exit 1}' "$MANIFEST_FILE"
}
EXPECTED_FILE="$(manifest_value backup_file)"
EXPECTED_SHA="$(manifest_value backup_sha256)"
[[ "$EXPECTED_FILE" == "$BASE" ]] || { echo "Backup manifest filename mismatch." >&2; exit 1; }
[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "Backup manifest SHA-256 is invalid." >&2; exit 1; }
(
  cd "$BACKUP_DIR_REAL"
  sha256sum --check "$(basename "$SHA_FILE")" >/dev/null
)
ACTUAL_SHA="$(sha256sum "$BACKUP_PATH" | awk '{print $1}')"
[[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] || { echo "Backup manifest SHA-256 mismatch." >&2; exit 1; }

# Serialize uploads with backup, retention, and isolated restore operations.
exec 9>"$RUNTIME_DIR/backup.lock"
flock -n 9 || {
  echo "Another FlowlessHub backup/restore/off-site operation is running." >&2
  exit 1
}

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
# Refuse implicit repository creation: provisioning/init is a separate owner-controlled step.
restic snapshots --json >/dev/null
restic backup --json \
  --tag flowlesshub \
  --tag "artifact=$BASE" \
  -- "$BACKUP_PATH" "$SHA_FILE" "$MANIFEST_FILE" >/dev/null

SNAPSHOTS_JSON="$(restic snapshots --json --tag "artifact=$BASE")"
SNAPSHOT_ID="$(printf '%s' "$SNAPSHOTS_JSON" | python3 -c '
import json, sys
expected_tag = "artifact=" + sys.argv[1]
snapshots = json.load(sys.stdin)
if not isinstance(snapshots, list):
    raise SystemExit("Unexpected restic snapshots JSON shape")
matching = [
    snapshot for snapshot in snapshots
    if "flowlesshub" in (snapshot.get("tags") or [])
    and expected_tag in (snapshot.get("tags") or [])
    and snapshot.get("id")
]
if not matching:
    raise SystemExit("No matching FlowlessHub artifact snapshot found after upload")
matching.sort(key=lambda snapshot: snapshot.get("time", ""))
print(matching[-1]["id"])
' "$BASE")"
[[ "$SNAPSHOT_ID" =~ ^[0-9a-f]{64}$ ]] || {
  echo "Restic snapshot ID could not be independently listed after upload." >&2
  exit 1
}

# A listable snapshot is metadata evidence only. Read every uploaded artifact
# back from that exact snapshot and compare its decrypted bytes with the local
# source before writing a marker that may later authorize local retention.
REMOTE_ARCHIVE_SHA=""
REMOTE_SIDECAR_SHA=""
REMOTE_MANIFEST_SHA=""
for file in "$BACKUP_PATH" "$SHA_FILE" "$MANIFEST_FILE"; do
  LOCAL_FILE_SHA="$(sha256sum "$file" | awk '{print $1}')"
  if ! REMOTE_FILE_SHA="$(restic dump "$SNAPSHOT_ID" "$file" | sha256sum | awk '{print $1}')"; then
    echo "Remote read-back failed: $(basename "$file")" >&2
    exit 1
  fi
  [[ "$REMOTE_FILE_SHA" =~ ^[0-9a-f]{64}$ && "$REMOTE_FILE_SHA" == "$LOCAL_FILE_SHA" ]] || {
    echo "Remote read-back SHA-256 mismatch: $(basename "$file")" >&2
    exit 1
  }
  case "$file" in
    "$BACKUP_PATH") REMOTE_ARCHIVE_SHA="$REMOTE_FILE_SHA" ;;
    "$SHA_FILE") REMOTE_SIDECAR_SHA="$REMOTE_FILE_SHA" ;;
    "$MANIFEST_FILE") REMOTE_MANIFEST_SHA="$REMOTE_FILE_SHA" ;;
  esac
done
[[ "$REMOTE_ARCHIVE_SHA" == "$ACTUAL_SHA" ]] || {
  echo "Remote archive read-back does not match the manifest archive checksum." >&2
  exit 1
}

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
MARKER="$BACKUP_PATH.offsite-uploaded"
TMP_MARKER="$(mktemp "$BACKUP_DIR/.$BASE.offsite.XXXXXX")"
cleanup() { rm -f -- "$TMP_MARKER"; }
trap cleanup EXIT
cat > "$TMP_MARKER" <<MARKER
format=restic-s3-readback-v2
backup_file=$BASE
backup_sha256=$ACTUAL_SHA
remote_archive_sha256=$REMOTE_ARCHIVE_SHA
remote_sha256_sidecar_sha256=$REMOTE_SIDECAR_SHA
remote_manifest_sha256=$REMOTE_MANIFEST_SHA
readback_verified=archive-and-sidecars
restic_snapshot_id=$SNAPSHOT_ID
uploaded_at_utc=$STAMP
MARKER
chmod 600 "$TMP_MARKER"
mv -- "$TMP_MARKER" "$MARKER"

printf 'Off-site upload completed; snapshot listing and remote archive/sidecar SHA-256 read-back confirmed.\n'
printf 'Archive: %s\n' "$BASE"
printf 'SHA-256: %s\n' "$ACTUAL_SHA"
printf 'Restic snapshot ID: %s\n' "$SNAPSHOT_ID"
printf 'Marker: %s\n' "$MARKER"
printf 'Note: targeted file read-back is not a PostgreSQL restore drill or full repository integrity audit.\n'
