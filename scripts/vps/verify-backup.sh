#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="$ROOT/.vps-runtime/backups"
POSTGRES_IMAGE="postgres:17.11-alpine"

usage() {
  echo "Usage: $0 <path-to-flowlesshub-backup.dump>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
for command in docker realpath stat sha256sum awk; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

[[ -d "$BACKUP_DIR" ]] || { echo "Backup directory does not exist." >&2; exit 1; }
# Archive listing runs in a 128 MiB helper container; retain host headroom.
# shellcheck disable=SC2016 # AWK owns the memory field in this single-quoted program.
AVAILABLE_MIB="$(awk '/MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)"
if (( AVAILABLE_MIB < 256 )); then
  echo "Backup verification refused: MemAvailable=${AVAILABLE_MIB} MiB; minimum=256 MiB." >&2
  exit 1
fi
BACKUP_DIR_REAL="$(realpath -e -- "$BACKUP_DIR")"
BACKUP_PATH="$(realpath -e -- "$1")"
[[ "$(dirname "$BACKUP_PATH")" == "$BACKUP_DIR_REAL" ]] || {
  echo "Backup must be a direct artifact inside $BACKUP_DIR_REAL." >&2
  exit 1
}
[[ -f "$BACKUP_PATH" ]] || { echo "Backup archive is not a regular file." >&2; exit 1; }

BASE="$(basename "$BACKUP_PATH")"
[[ "$BASE" =~ ^flowlesshub-[0-9]{8}T[0-9]{6}Z\.dump$ ]] || {
  echo "Unexpected backup filename: $BASE" >&2
  exit 1
}
SHA_FILE="$BACKUP_PATH.sha256"
MANIFEST_FILE="$BACKUP_PATH.manifest"
[[ -f "$SHA_FILE" && -f "$MANIFEST_FILE" ]] || {
  echo "Backup checksum or manifest sidecar is missing." >&2
  exit 1
}

for file in "$BACKUP_PATH" "$SHA_FILE" "$MANIFEST_FILE"; do
  [[ "$(stat -c '%a' "$file")" == "600" ]] || {
    echo "Backup artifact must have mode 600: $(basename "$file")" >&2
    exit 1
  }
done

manifest_value() {
  local key="$1"
  # shellcheck disable=SC2016 # AWK owns the record fields in this single-quoted program.
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; found=1; exit} END {if (!found) exit 1}' "$MANIFEST_FILE"
}

FORMAT="$(manifest_value format)"
MANIFEST_FILE_NAME="$(manifest_value backup_file)"
MANIFEST_SHA="$(manifest_value backup_sha256)"
SOURCE_COMMIT="$(manifest_value source_commit)"
ACTIVE_COLOR="$(manifest_value active_color)"
PG_VERSION="$(manifest_value postgres_server_version)"
CREATED_AT="$(manifest_value created_at_utc)"
DB_SIZE_BYTES="$(manifest_value database_size_bytes)"
USER_SCHEMA_COUNT="$(manifest_value user_schema_count)"
USER_RELATION_COUNT="$(manifest_value user_relation_count)"

[[ "$FORMAT" == "postgres-custom" ]] || { echo "Unsupported backup format." >&2; exit 1; }
[[ "$MANIFEST_FILE_NAME" == "$BASE" ]] || { echo "Manifest filename does not match archive." >&2; exit 1; }
[[ "$MANIFEST_SHA" =~ ^[0-9a-f]{64}$ ]] || { echo "Manifest checksum is invalid." >&2; exit 1; }
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "Manifest source commit is invalid." >&2; exit 1; }
[[ "$ACTIVE_COLOR" == "blue" || "$ACTIVE_COLOR" == "green" ]] || { echo "Manifest active color is invalid." >&2; exit 1; }
[[ "$PG_VERSION" =~ ^17\. ]] || { echo "Expected PostgreSQL 17 archive metadata." >&2; exit 1; }
[[ "$CREATED_AT" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || { echo "Manifest timestamp is invalid." >&2; exit 1; }
if [[ ! "$DB_SIZE_BYTES" =~ ^[0-9]+$ ]] || (( DB_SIZE_BYTES <= 0 )); then
  echo "Manifest database size is invalid." >&2
  exit 1
fi
[[ "$USER_SCHEMA_COUNT" =~ ^[0-9]+$ && "$USER_RELATION_COUNT" =~ ^[0-9]+$ ]] || {
  echo "Manifest schema/relation counts are invalid." >&2
  exit 1
}

(
  cd "$BACKUP_DIR_REAL"
  sha256sum --check "$(basename "$SHA_FILE")"
)

# shellcheck disable=SC2016 # AWK owns the positional field in this single-quoted program.
ACTUAL_SHA="$(sha256sum "$BACKUP_PATH" | awk '{print $1}')"
[[ "$ACTUAL_SHA" == "$MANIFEST_SHA" ]] || { echo "Manifest SHA-256 mismatch." >&2; exit 1; }

docker image inspect "$POSTGRES_IMAGE" >/dev/null 2>&1 || {
  echo "Required local validation image is missing: $POSTGRES_IMAGE. Refusing an implicit pull." >&2
  exit 1
}

docker run --rm \
  --network none \
  --memory 128m \
  --memory-swap 128m \
  --cpus 0.25 \
  --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m \
  --mount "type=bind,src=$BACKUP_DIR_REAL,dst=/backups,readonly" \
  "$POSTGRES_IMAGE" \
  pg_restore --list "/backups/$BASE" >/dev/null

printf 'Backup verification passed.\n'
printf 'Archive: %s\n' "$BACKUP_PATH"
printf 'SHA-256: %s\n' "$ACTUAL_SHA"
printf 'Source commit: %s\n' "$SOURCE_COMMIT"
printf 'PostgreSQL version: %s\n' "$PG_VERSION"
printf 'Recorded user schemas: %s\n' "$USER_SCHEMA_COUNT"
printf 'Recorded user relations: %s\n' "$USER_RELATION_COUNT"
