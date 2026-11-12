#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <blue|green> <sha-40-hex-commit>" >&2
  exit 2
fi
COLOR="$1"
TAG="$2"
[[ "$COLOR" == "blue" || "$COLOR" == "green" ]] || { echo "Color must be blue or green." >&2; exit 2; }
[[ "$TAG" =~ ^sha-[0-9a-f]{40}$ ]] || { echo "Release must be a commit-addressed sha-<40 lowercase hex> image tag." >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.vps-runtime/.env"
ACTIVE_FILE="$ROOT/.vps-runtime/active-color"
RUNTIME_DIR="$ROOT/.vps-runtime"
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
[[ -f "$ACTIVE_FILE" ]] || { echo "No active-color marker; set-release is only for an existing deployment." >&2; exit 1; }
ACTIVE_COLOR="$(tr -d '\r\n' < "$ACTIVE_FILE")"
[[ "$ACTIVE_COLOR" == "blue" || "$ACTIVE_COLOR" == "green" ]] || { echo "Invalid active-color marker: $ACTIVE_COLOR" >&2; exit 1; }
[[ "$COLOR" != "$ACTIVE_COLOR" ]] || { echo "Refusing to change the currently active $ACTIVE_COLOR image reference. Target the inactive color." >&2; exit 1; }

exec 9>"$RUNTIME_DIR/deploy.lock"
flock -n 9 || { echo "Another FlowlessHub deployment operation is already running." >&2; exit 1; }
chmod 600 "$ENV_FILE"
BACKUP="$(mktemp "${ENV_FILE}.bak.XXXXXX")"
cp -p "$ENV_FILE" "$BACKUP"
chmod 600 "$BACKUP"
TMP_ENV="$(mktemp "${ENV_FILE}.XXXXXX")"
cleanup() { rm -f "$TMP_ENV"; }
trap cleanup EXIT

COLOR_KEY="FLOWLESSHUB_$(printf '%s' "$COLOR" | tr '[:lower:]' '[:upper:]')_RELEASE"
# shellcheck disable=SC2016 # AWK owns the record variable $0; it must not expand in Bash.
awk -v color_key="$COLOR_KEY" -v release="$TAG" '
  BEGIN {
    keys[color_key] = release
    keys["FLOWLESSHUB_WORKER_RELEASE"] = release
    keys["FLOWLESSHUB_MIGRATE_RELEASE"] = release
  }
  {
    separator = index($0, "=")
    key = separator > 0 ? substr($0, 1, separator - 1) : ""
    if (key in keys) {
      if (seen[key]++) {
        duplicate = 1
        next
      }
      print key "=" keys[key]
      next
    }
    print
  }
  END {
    if (duplicate) exit 2
    for (key in keys) if (!seen[key]) print key "=" keys[key]
  }
' "$ENV_FILE" > "$TMP_ENV"
chmod 600 "$TMP_ENV"

# Validate the candidate env file before replacing the live one.
docker compose --env-file "$TMP_ENV" -f "$ROOT/deploy/compose/vps.compose.yaml" config --quiet
mv "$TMP_ENV" "$ENV_FILE"
trap - EXIT

printf 'Updated %s release reference to %s. Other color remains pinned for rollback.\n' "$COLOR" "$TAG"
printf 'Worker and migration references were updated atomically. Protected backup: %s\n' "$BACKUP"
printf 'No running service was changed.\n'
