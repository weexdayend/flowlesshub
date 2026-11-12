#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.vps-runtime/.env"
RUNTIME_DIR="$ROOT/.vps-runtime"
COMPOSE_FILE="$ROOT/deploy/compose/vps.compose.yaml"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
if [[ "${FLOWLESSHUB_DEPLOY_LOCK_HELD:-0}" == "1" ]]; then
  inherited_lock="$(readlink "/proc/$$/fd/9" 2>/dev/null || true)"
  [[ "$inherited_lock" == "$RUNTIME_DIR/deploy.lock" ]] || { echo "The inherited deployment lock descriptor is invalid." >&2; exit 1; }
  flock -n 9 || { echo "The inherited FlowlessHub deployment lock is not held." >&2; exit 1; }
else
  exec 9>"$RUNTIME_DIR/deploy.lock"
  flock -n 9 || { echo "Another FlowlessHub deployment operation is already running." >&2; exit 1; }
fi
"${COMPOSE[@]}" pull worker
"${COMPOSE[@]}" up -d --no-deps worker

ready=0
for ((attempt = 1; attempt <= 20; attempt++)); do
  ids="$("${COMPOSE[@]}" ps -q worker)"
  count="$(printf '%s\n' "$ids" | awk 'NF { n++ } END { print n + 0 }')"
  if [[ "$count" == "1" ]]; then
    container_id="$(printf '%s\n' "$ids" | head -n 1)"
    running="$(docker inspect --format '{{.State.Running}}' "$container_id")"
    worker_log="$("${COMPOSE[@]}" logs --no-color --tail=80 worker 2>/dev/null || true)"
    if [[ "$running" == "true" ]] && grep -Fq 'River worker started' <<< "$worker_log"; then
      ready=1
      break
    fi
  fi
  sleep 1
done

if (( ready == 0 )); then
  "${COMPOSE[@]}" ps
  "${COMPOSE[@]}" logs --tail=100 worker
  echo "Worker did not reach the expected single-running-process state." >&2
  exit 1
fi

printf 'Exactly one FlowlessHub River worker is running and startup was observed.\n'
printf 'Business handlers remain unregistered in this checkpoint; do not scale the worker.\n'
