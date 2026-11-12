#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_DIR="$ROOT/.vps-runtime"
ENV_FILE="$RUNTIME_DIR/.env"
ACTIVE_FILE="$RUNTIME_DIR/active-color"
COMPOSE_FILE="$ROOT/deploy/compose/vps.compose.yaml"

[[ -f "$ACTIVE_FILE" && -f "$ENV_FILE" ]] || { echo "Missing runtime env or active-color state." >&2; exit 1; }

# Hold the lock before reading release state and retain it through Web/API + worker rollback.
exec 9>"$RUNTIME_DIR/deploy.lock"
flock -n 9 || { echo "Another FlowlessHub deployment operation is already running." >&2; exit 1; }

CURRENT="$(tr -d '\r\n' < "$ACTIVE_FILE")"
case "$CURRENT" in
  blue) TARGET=green ;;
  green) TARGET=blue ;;
  *) echo "Invalid active-color marker: $CURRENT" >&2; exit 1 ;;
esac

TARGET_UPPER="$(printf '%s' "$TARGET" | tr '[:lower:]' '[:upper:]')"
TARGET_RELEASE="$(sed -n "s/^FLOWLESSHUB_${TARGET_UPPER}_RELEASE=//p" "$ENV_FILE" | tail -1)"
[[ "$TARGET_RELEASE" =~ ^sha-[0-9a-f]{40}$ ]] || { echo "Invalid pinned release for rollback target $TARGET." >&2; exit 1; }
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --quiet

# Child scripts verify and reuse inherited descriptor 9 instead of opening a new lock.
FLOWLESSHUB_DEPLOY_LOCK_HELD=1 "$ROOT/scripts/vps/switch-color.sh" "$TARGET"

BACKUP="$(mktemp "${ENV_FILE}.rollback.XXXXXX")"
cp -p "$ENV_FILE" "$BACKUP"
chmod 600 "$BACKUP"
TMP_ENV="$(mktemp "${ENV_FILE}.rollback.XXXXXX")"
cleanup() { [[ -z "${TMP_ENV:-}" ]] || rm -f "$TMP_ENV"; }
trap cleanup EXIT

awk -v release="$TARGET_RELEASE" '
  /^FLOWLESSHUB_WORKER_RELEASE=/ { print "FLOWLESSHUB_WORKER_RELEASE=" release; found=1; next }
  { print }
  END { if (!found) print "FLOWLESSHUB_WORKER_RELEASE=" release }
' "$ENV_FILE" > "$TMP_ENV"
chmod 600 "$TMP_ENV"
docker compose --env-file "$TMP_ENV" -f "$COMPOSE_FILE" config --quiet
mv "$TMP_ENV" "$ENV_FILE"
TMP_ENV=""
trap - EXIT

FLOWLESSHUB_DEPLOY_LOCK_HELD=1 "$ROOT/scripts/vps/update-worker.sh"
printf 'Rollback completed for Web/API and restored the worker to the same release. Database schema was not rolled back.\n'
