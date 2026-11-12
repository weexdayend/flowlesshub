#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 || ( "$1" != "blue" && "$1" != "green" ) ]]; then
  echo "Usage: $0 <blue|green>" >&2
  exit 2
fi
TARGET="$1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.vps-runtime/.env"
RUNTIME_DIR="$ROOT/.vps-runtime"
CADDY_DIR="$RUNTIME_DIR/caddy"
ACTIVE_FILE="$RUNTIME_DIR/active-color"
COMPOSE_FILE="$ROOT/deploy/compose/vps.compose.yaml"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

[[ -f "$ACTIVE_FILE" ]] || { echo "No active-color state; run deploy-initial.sh first." >&2; exit 1; }
CURRENT="$(tr -d '\r\n' < "$ACTIVE_FILE")"
[[ "$CURRENT" == "blue" || "$CURRENT" == "green" ]] || { echo "Invalid active-color marker." >&2; exit 1; }
if [[ "$CURRENT" == "$TARGET" ]]; then
  echo "$TARGET is already active. No action taken."
  exit 0
fi

MIN_AVAILABLE_MIB="$(sed -n 's/^FLOWLESSHUB_MIN_AVAILABLE_MIB=//p' "$ENV_FILE" | tail -1)"
MIN_AVAILABLE_MIB="${MIN_AVAILABLE_MIB:-384}"
API_SERVICE="api-$TARGET"
WEB_SERVICE="web-$TARGET"
CANDIDATE_FILE="$ROOT/deploy/vps/Caddyfile.$TARGET"

# Reusing an already-running inactive color does not add another pair of app containers.
API_WAS_RUNNING="$(docker ps -q --filter "label=com.docker.compose.project=flowlesshub-vps" --filter "label=com.docker.compose.service=$API_SERVICE" --filter status=running)"
WEB_WAS_RUNNING="$(docker ps -q --filter "label=com.docker.compose.project=flowlesshub-vps" --filter "label=com.docker.compose.service=$WEB_SERVICE" --filter status=running)"
TARGET_WAS_RUNNING=0
if [[ -n "$API_WAS_RUNNING" && -n "$WEB_WAS_RUNNING" ]]; then
  TARGET_WAS_RUNNING=1
else
  AVAILABLE_MIB="$(awk '/MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)"
  if (( AVAILABLE_MIB < MIN_AVAILABLE_MIB )); then
    echo "Refusing blue/green overlap: MemAvailable=${AVAILABLE_MIB} MiB, required=${MIN_AVAILABLE_MIB} MiB." >&2
    echo "Do not stop the active color. Upgrade RAM or reduce unrelated workloads, then retry." >&2
    exit 1
  fi
fi

stop_candidate() {
  # The target is always inactive until the Caddy switch and probes succeed.
  # Stop it on failure to release memory; the current active color is untouched.
  "${COMPOSE[@]}" stop "$API_SERVICE" "$WEB_SERVICE" || true
}
[[ -f "$CANDIDATE_FILE" ]] || { echo "Missing Caddyfile for $TARGET." >&2; exit 1; }

"${COMPOSE[@]}" pull "$API_SERVICE" "$WEB_SERVICE"
"${COMPOSE[@]}" --profile "$TARGET" up -d --no-deps "$API_SERVICE" "$WEB_SERVICE"

docker pull curlimages/curl:8.12.1
candidate_ready=0
for attempt in $(seq 1 40); do
  if docker run --rm --network flowlesshub-vps-edge curlimages/curl:8.12.1 -fsS --max-time 3 "http://${API_SERVICE}:5050/readyz" >/dev/null 2>&1 && \
     docker run --rm --network flowlesshub-vps-edge curlimages/curl:8.12.1 -fsS --max-time 5 "http://${WEB_SERVICE}:3000/" >/dev/null 2>&1; then
    candidate_ready=1
    break
  fi
  sleep 3
done
if (( candidate_ready == 0 )); then
  "${COMPOSE[@]}" logs --tail=100 "$API_SERVICE" "$WEB_SERVICE"
  stop_candidate
  echo "Candidate health checks failed; active color remains $CURRENT." >&2
  exit 1
fi

AFTER_MIB="$(awk '/MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)"
if (( AFTER_MIB < 256 )); then
  echo "Candidate is healthy but MemAvailable fell to ${AFTER_MIB} MiB; refusing traffic switch." >&2
  echo "Stopping only the inactive candidate to protect Petshop and the active color." >&2
  stop_candidate
  exit 1
fi

BACKUP="$CADDY_DIR/Caddyfile.rollback"
cp "$CADDY_DIR/Caddyfile" "$BACKUP"
cp "$CANDIDATE_FILE" "$CADDY_DIR/Caddyfile"
if ! "${COMPOSE[@]}" exec -T edge caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile; then
  cp "$BACKUP" "$CADDY_DIR/Caddyfile"
  "${COMPOSE[@]}" exec -T edge caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile || true
  stop_candidate
  exit 1
fi
if ! "${COMPOSE[@]}" exec -T edge caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile; then
  cp "$BACKUP" "$CADDY_DIR/Caddyfile"
  "${COMPOSE[@]}" exec -T edge caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile || true
  stop_candidate
  echo "Caddy reload failed; restored previous config. Active color remains $CURRENT." >&2
  exit 1
fi

routed_ready=0
for attempt in $(seq 1 20); do
  if curl -fsS --max-time 3 http://127.0.0.1:5052/readyz >/dev/null 2>&1 && \
     curl -fsS --max-time 5 http://127.0.0.1:3032/ >/dev/null 2>&1; then
    routed_ready=1
    break
  fi
  sleep 1
done
if (( routed_ready == 0 )); then
  cp "$BACKUP" "$CADDY_DIR/Caddyfile"
  "${COMPOSE[@]}" exec -T edge caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile || true
  stop_candidate
  echo "Post-switch probes failed; restored Caddy config to $CURRENT." >&2
  exit 1
fi

printf '%s\n' "$TARGET" > "$ACTIVE_FILE"
chmod 600 "$ACTIVE_FILE"
rm -f "$BACKUP"
printf 'Traffic successfully switched: %s -> %s. Previous color is still running for rollback.\n' "$CURRENT" "$TARGET"
printf 'Next: update the single worker, observe health/resource use, then stop old color only after acceptance.\n'
