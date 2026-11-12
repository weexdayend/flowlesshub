#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <blue|green> <sha-40-hex-commit>" >&2
  exit 2
fi
COLOR="$1"
TAG="$2"
[[ "$COLOR" == "blue" || "$COLOR" == "green" ]] || { echo "Color must be blue or green." >&2; exit 2; }
[[ "$TAG" =~ ^sha-[0-9a-f]{40}$ ]] || { echo "Release must be a commit-addressed sha-<40 lowercase hex> tag." >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.vps-runtime/.env"
ACTIVE_FILE="$ROOT/.vps-runtime/active-color"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
[[ -f "$ACTIVE_FILE" ]] || { echo "No active-color marker; set-release is only for an existing deployment." >&2; exit 1; }
ACTIVE_COLOR="$(tr -d '\r\n' < "$ACTIVE_FILE")"
[[ "$ACTIVE_COLOR" == "blue" || "$ACTIVE_COLOR" == "green" ]] || { echo "Invalid active-color marker: $ACTIVE_COLOR" >&2; exit 1; }
[[ "$COLOR" != "$ACTIVE_COLOR" ]] || { echo "Refusing to change the currently active $ACTIVE_COLOR image reference. Target the inactive color." >&2; exit 1; }
chmod 600 "$ENV_FILE"
cp -p "$ENV_FILE" "$ENV_FILE.bak.$(date -u +%Y%m%dT%H%M%SZ)"

set_value() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp "${ENV_FILE}.XXXXXX")"
  awk -v key="$key" -v value="$value" '
    BEGIN { found=0 }
    index($0, key "=") == 1 { print key "=" value; found=1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$ENV_FILE" > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$ENV_FILE"
}

upper="$(printf '%s' "$COLOR" | tr '[:lower:]' '[:upper:]')"
set_value "FLOWLESSHUB_${upper}_RELEASE" "$TAG"
set_value FLOWLESSHUB_WORKER_RELEASE "$TAG"
set_value FLOWLESSHUB_MIGRATE_RELEASE "$TAG"

docker compose --env-file "$ENV_FILE" -f "$ROOT/deploy/compose/vps.compose.yaml" config --quiet
printf 'Updated %s release reference to %s. Other color remains pinned for rollback.\n' "$COLOR" "$TAG"
printf 'A protected .env backup was created; no running service was changed.\n'
