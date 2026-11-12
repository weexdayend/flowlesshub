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

[[ -f "$ENV_FILE" && -f "$ACTIVE_FILE" ]] || { echo "Missing runtime env or active-color state; run deploy-initial.sh first." >&2; exit 1; }
if [[ "${FLOWLESSHUB_DEPLOY_LOCK_HELD:-0}" == "1" ]]; then
  inherited_lock="$(readlink "/proc/$$/fd/9" 2>/dev/null || true)"
  [[ "$inherited_lock" == "$RUNTIME_DIR/deploy.lock" ]] || { echo "The inherited deployment lock descriptor is invalid." >&2; exit 1; }
  flock -n 9 || { echo "The inherited FlowlessHub deployment lock is not held." >&2; exit 1; }
else
  exec 9>"$RUNTIME_DIR/deploy.lock"
  flock -n 9 || { echo "Another FlowlessHub deployment operation is already running." >&2; exit 1; }
fi

CURRENT="$(tr -d '\r\n' < "$ACTIVE_FILE")"
[[ "$CURRENT" == "blue" || "$CURRENT" == "green" ]] || { echo "Invalid active-color marker." >&2; exit 1; }
if [[ "$CURRENT" == "$TARGET" ]]; then
  echo "$TARGET is already active. No action taken."
  exit 0
fi

MIN_AVAILABLE_MIB="$(sed -n 's/^FLOWLESSHUB_MIN_AVAILABLE_MIB=//p' "$ENV_FILE" | tail -1)"
MIN_AVAILABLE_MIB="${MIN_AVAILABLE_MIB:-384}"
[[ "$MIN_AVAILABLE_MIB" =~ ^[0-9]+$ ]] && (( MIN_AVAILABLE_MIB >= 384 )) || { echo "FLOWLESSHUB_MIN_AVAILABLE_MIB cannot be lower than the 384 MiB blue-green safety floor." >&2; exit 1; }
API_SERVICE="api-$TARGET"
WEB_SERVICE="web-$TARGET"
CANDIDATE_FILE="$ROOT/deploy/vps/Caddyfile.$TARGET"
ACTIVE_CADDYFILE="$CADDY_DIR/Caddyfile"
[[ -f "$CANDIDATE_FILE" && -f "$ACTIVE_CADDYFILE" ]] || { echo "Missing candidate or active Caddyfile." >&2; exit 1; }

# Serialize the switch and retain a rollback copy until state is committed.
BACKUP="$(mktemp "$CADDY_DIR/Caddyfile.rollback.XXXXXX")"
cp "$ACTIVE_CADDYFILE" "$BACKUP"
CANDIDATE_STARTED=0
CADDY_CONFIG_REPLACED=0
ACTIVE_MARKER_WRITTEN=0
SWITCH_COMMITTED=0

stop_candidate() {
  "${COMPOSE[@]}" stop "$API_SERVICE" "$WEB_SERVICE" >/dev/null 2>&1 || true
}

cleanup() {
  status=$?
  trap - EXIT
  restore_failed=0
  if (( status != 0 && SWITCH_COMMITTED == 0 )); then
    if (( CADDY_CONFIG_REPLACED == 1 )); then
      restore_tmp="$(mktemp "$CADDY_DIR/Caddyfile.restore.XXXXXX")" || restore_failed=1
      if (( restore_failed == 0 )); then
        if cp "$BACKUP" "$restore_tmp" && chmod 644 "$restore_tmp" && mv "$restore_tmp" "$ACTIVE_CADDYFILE"; then
          if ! "${COMPOSE[@]}" exec -T edge caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
            echo "WARNING: prior Caddy config is restored on disk, but reload could not be confirmed." >&2
            restore_failed=1
          fi
        else
          rm -f "$restore_tmp"
          echo "WARNING: automatic Caddy config restoration failed. Preserve backup: $BACKUP" >&2
          restore_failed=1
        fi
      fi
    fi
    if (( ACTIVE_MARKER_WRITTEN == 1 )); then
      state_restore_tmp="$(mktemp "$RUNTIME_DIR/active-color.restore.XXXXXX")" || state_restore_tmp=""
      if [[ -n "$state_restore_tmp" ]] && printf '%s\n' "$CURRENT" > "$state_restore_tmp" && chmod 600 "$state_restore_tmp" && mv "$state_restore_tmp" "$ACTIVE_FILE"; then
        :
      else
        [[ -z "$state_restore_tmp" ]] || rm -f "$state_restore_tmp"
        echo "WARNING: failed to restore active-color marker; set it back to $CURRENT after inspecting Caddy routing." >&2
        restore_failed=1
      fi
    fi
    if (( CANDIDATE_STARTED == 1 )); then
      stop_candidate
    fi
    echo "Candidate switch did not commit; expected active-color remains $CURRENT." >&2
  fi
  for temporary_file in "${CADDY_TMP:-}" "${STATE_TMP:-}" "${restore_tmp:-}" "${state_restore_tmp:-}"; do
    [[ -z "$temporary_file" ]] || rm -f "$temporary_file" || true
  done
  if (( restore_failed == 0 )); then
    rm -f "$BACKUP"
  else
    echo "Manual recovery backup retained at: $BACKUP" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

# Reusing an already-running inactive color does not add another app pair.
API_WAS_RUNNING="$(docker ps -q --filter "label=com.docker.compose.project=flowlesshub-vps" --filter "label=com.docker.compose.service=$API_SERVICE" --filter status=running)"
WEB_WAS_RUNNING="$(docker ps -q --filter "label=com.docker.compose.project=flowlesshub-vps" --filter "label=com.docker.compose.service=$WEB_SERVICE" --filter status=running)"
if [[ -z "$API_WAS_RUNNING" || -z "$WEB_WAS_RUNNING" ]]; then
  # shellcheck disable=SC2016 # AWK owns the positional field in this single-quoted program.
  AVAILABLE_MIB="$(awk '/MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)"
  if (( AVAILABLE_MIB < MIN_AVAILABLE_MIB )); then
    echo "Refusing blue/green overlap: MemAvailable=${AVAILABLE_MIB} MiB, required=${MIN_AVAILABLE_MIB} MiB." >&2
    echo "Do not stop the active color or lower the guard just to force deployment." >&2
    exit 1
  fi
fi

"${COMPOSE[@]}" pull "$API_SERVICE" "$WEB_SERVICE"
CANDIDATE_STARTED=1
"${COMPOSE[@]}" --profile "$TARGET" up -d --no-deps "$API_SERVICE" "$WEB_SERVICE"

docker pull curlimages/curl:8.12.1
candidate_ready=0
for ((attempt = 1; attempt <= 40; attempt++)); do
  if docker run --rm --network flowlesshub-vps-edge curlimages/curl:8.12.1 -fsS --max-time 3 "http://${API_SERVICE}:5050/readyz" >/dev/null 2>&1 && \
     docker run --rm --network flowlesshub-vps-edge curlimages/curl:8.12.1 -fsS --max-time 5 "http://${WEB_SERVICE}:3000/" >/dev/null 2>&1; then
    candidate_ready=1
    break
  fi
  sleep 3
done
if (( candidate_ready == 0 )); then
  "${COMPOSE[@]}" logs --tail=100 "$API_SERVICE" "$WEB_SERVICE"
  echo "Candidate health checks failed." >&2
  exit 1
fi

# shellcheck disable=SC2016 # AWK owns the positional field in this single-quoted program.
AFTER_MIB="$(awk '/MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)"
if (( AFTER_MIB < 256 )); then
  echo "Candidate is healthy but MemAvailable fell to ${AFTER_MIB} MiB; refusing traffic switch." >&2
  echo "The inactive candidate will be stopped; active service remains selected." >&2
  exit 1
fi

CADDY_TMP="$(mktemp "$CADDY_DIR/Caddyfile.candidate.XXXXXX")"
cp "$CANDIDATE_FILE" "$CADDY_TMP"
chmod 644 "$CADDY_TMP"
CADDY_CONFIG_REPLACED=1
mv "$CADDY_TMP" "$ACTIVE_CADDYFILE"

"${COMPOSE[@]}" exec -T edge caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
"${COMPOSE[@]}" exec -T edge caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile

routed_ready=0
for ((attempt = 1; attempt <= 20; attempt++)); do
  if curl -fsS --max-time 3 http://127.0.0.1:5052/readyz >/dev/null 2>&1 && \
     curl -fsS --max-time 5 http://127.0.0.1:3032/ >/dev/null 2>&1; then
    routed_ready=1
    break
  fi
  sleep 1
done
if (( routed_ready == 0 )); then
  echo "Post-switch loopback probes failed." >&2
  exit 1
fi

STATE_TMP="$(mktemp "$RUNTIME_DIR/active-color.XXXXXX")"
printf '%s\n' "$TARGET" > "$STATE_TMP"
chmod 600 "$STATE_TMP"
ACTIVE_MARKER_WRITTEN=1
mv "$STATE_TMP" "$ACTIVE_FILE"
SWITCH_COMMITTED=1
printf 'Traffic successfully switched: %s -> %s. Previous color remains available for rollback.\n' "$CURRENT" "$TARGET"
printf 'Next: update the single worker, observe health/resource use, then stop the old color only after acceptance.\n'
