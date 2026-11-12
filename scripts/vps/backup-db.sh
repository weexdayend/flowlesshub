#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.vps-runtime/.env"
COMPOSE_FILE="$ROOT/deploy/compose/vps.compose.yaml"
BACKUP_DIR="$ROOT/.vps-runtime/backups"

[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
mkdir -p "$BACKUP_DIR"
chmod 700 "$ROOT/.vps-runtime" "$BACKUP_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$BACKUP_DIR/flowlesshub-${STAMP}.dump"
[[ ! -e "$OUT" ]] || { echo "Backup file already exists: $OUT" >&2; exit 1; }
validated=0
cleanup_incomplete_backup() {
  if (( validated == 0 )); then
    rm -f "$OUT"
  fi
}
trap cleanup_incomplete_backup EXIT

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T postgres sh -ec \
  "exec pg_dump --format=custom --no-owner --username=\"\$POSTGRES_USER\" --dbname=\"\$POSTGRES_DB\"" > "$OUT"
docker run --rm -v "$BACKUP_DIR:/backups:ro" postgres:17.11-alpine \
  pg_restore --list "/backups/$(basename "$OUT")" >/dev/null
validated=1
chmod 600 "$OUT"

printf 'Database backup created and archive-list validation passed: %s\n' "$OUT"
printf 'Copy this backup off-host before production migrations/releases.\n'
