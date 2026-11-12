#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ACTIVE_FILE="$ROOT/.vps-runtime/active-color"
[[ -f "$ACTIVE_FILE" ]] || { echo "No active-color state." >&2; exit 1; }
CURRENT="$(tr -d '\r\n' < "$ACTIVE_FILE")"
case "$CURRENT" in
  blue) TARGET=green ;;
  green) TARGET=blue ;;
  *) echo "Invalid active-color marker: $CURRENT" >&2; exit 1 ;;
esac
"$ROOT/scripts/vps/switch-color.sh" "$TARGET"

ENV_FILE="$ROOT/.vps-runtime/.env"
TARGET_UPPER="$(printf '%s' "$TARGET" | tr '[:lower:]' '[:upper:]')"
TARGET_RELEASE="$(sed -n "s/^FLOWLESSHUB_${TARGET_UPPER}_RELEASE=//p" "$ENV_FILE" | tail -1)"
[[ "$TARGET_RELEASE" =~ ^sha-[0-9a-f]{40}$ ]] || { echo "Invalid pinned release for rollback target $TARGET." >&2; exit 1; }
cp -p "$ENV_FILE" "$ENV_FILE.rollback.$(date -u +%Y%m%dT%H%M%SZ)"
TMP_ENV="$(mktemp "${ENV_FILE}.XXXXXX")"
awk -v release="$TARGET_RELEASE" '
  /^FLOWLESSHUB_WORKER_RELEASE=/ { print "FLOWLESSHUB_WORKER_RELEASE=" release; found=1; next }
  { print }
  END { if (!found) print "FLOWLESSHUB_WORKER_RELEASE=" release }
' "$ENV_FILE" > "$TMP_ENV"
chmod 600 "$TMP_ENV"
docker compose --env-file "$TMP_ENV" -f "$ROOT/deploy/compose/vps.compose.yaml" config --quiet
mv "$TMP_ENV" "$ENV_FILE"
"$ROOT/scripts/vps/update-worker.sh"
printf 'Rollback completed for Web/API and restored the worker to the same release. Database schema was not rolled back.\n'
