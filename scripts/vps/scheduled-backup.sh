#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_DIR="$ROOT/.vps-runtime"
BACKUP_SCRIPT="$ROOT/scripts/vps/backup-db.sh"
OFFSITE_SCRIPT="$ROOT/scripts/vps/offsite-backup.sh"
RETENTION_SCRIPT="$ROOT/scripts/vps/backup-retention.sh"
RETENTION_POLICY="$RUNTIME_DIR/backup-retention.env"

for command in awk mktemp stat; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done
[[ -x "$BACKUP_SCRIPT" && -x "$OFFSITE_SCRIPT" && -x "$RETENTION_SCRIPT" ]] || {
  echo "Scheduled backup scripts must be present and executable." >&2
  exit 1
}

mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"
OUTPUT_FILE="$(mktemp "$RUNTIME_DIR/.scheduled-backup.XXXXXX")"
cleanup() { rm -f -- "$OUTPUT_FILE"; }
trap cleanup EXIT

if ! "$BACKUP_SCRIPT" > "$OUTPUT_FILE"; then
  cat "$OUTPUT_FILE" >&2
  echo "Scheduled backup failed; off-site and retention steps were not started." >&2
  exit 1
fi
cat "$OUTPUT_FILE"

if ! ARCHIVE="$(awk -F': ' '/^Archive: / {if (!seen[$2]++) {archive=$2; count++}} END {if (count != 1) exit 1; print archive}' "$OUTPUT_FILE")"; then
  echo "backup-db.sh did not return exactly one unique archive path." >&2
  exit 1
fi
[[ "$ARCHIVE" == "$RUNTIME_DIR/backups/"* && "$ARCHIVE" == *.dump ]] || {
  echo "backup-db.sh did not return one expected archive path." >&2
  exit 1
}
[[ -f "$ARCHIVE" && ! -L "$ARCHIVE" ]] || {
  echo "Scheduled backup archive is missing or unsafe." >&2
  exit 1
}

set +e
"$OFFSITE_SCRIPT" "$ARCHIVE"
OFFSITE_STATUS=$?
set -e
case "$OFFSITE_STATUS" in
  0) printf 'Off-site stage: uploaded and snapshot listing confirmed.\n' ;;
  3) printf 'Off-site stage: not configured or disabled; local backup retained.\n' ;;
  *)
    echo "Off-site upload failed; retention was not started." >&2
    exit "$OFFSITE_STATUS"
    ;;
esac

AUTO_PRUNE=0
if [[ -e "$RETENTION_POLICY" ]]; then
  [[ -f "$RETENTION_POLICY" && ! -L "$RETENTION_POLICY" ]] || {
    echo "Retention policy must be a regular non-symlink file." >&2
    exit 1
  }
  [[ "$(stat -c '%a' "$RETENTION_POLICY")" == "600" ]] || {
    echo "Retention policy must have mode 600." >&2
    exit 1
  }
  [[ "$(stat -c '%u' "$RETENTION_POLICY")" == "$(id -u)" ]] || {
    echo "Retention policy must be owned by the account running this script." >&2
    exit 1
  }
  # This is an operator-managed shell environment file; do not accept group/other-writable input.
  # shellcheck disable=SC1090
  set -a
  . "$RETENTION_POLICY"
  set +a
  AUTO_PRUNE="${FLOWLESSHUB_BACKUP_RETENTION_AUTO_PRUNE:-0}"
fi

if [[ "$AUTO_PRUNE" == "1" ]]; then
  "$RETENTION_SCRIPT" --apply
else
  "$RETENTION_SCRIPT" --dry-run
fi

printf 'Scheduled backup workflow completed. Review this unit in journald for upload/retention state.\n'
