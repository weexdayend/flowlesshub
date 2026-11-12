#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.vps-runtime/.env"
COMPOSE_FILE="$ROOT/deploy/compose/vps.compose.yaml"
RUNTIME_DIR="$ROOT/.vps-runtime"
CADDY_DIR="$RUNTIME_DIR/caddy"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
mkdir -p "$RUNTIME_DIR" "$CADDY_DIR" "$RUNTIME_DIR/backups"
chmod 700 "$RUNTIME_DIR" "$RUNTIME_DIR/backups"
chmod 755 "$CADDY_DIR"
exec 9>"$RUNTIME_DIR/deploy.lock"
flock -n 9 || { echo "Another FlowlessHub deployment operation is already running." >&2; exit 1; }

"$ROOT/scripts/vps/preflight.sh"

if [[ -f "$RUNTIME_DIR/active-color" ]]; then
  echo "FlowlessHub already has an active-color marker. Use the release runbook, not first-install script." >&2
  exit 1
fi

# A prior first-install attempt may have created FlowlessHub containers before a
# health check failed. Resume that project in place; never remove its volumes.
EXISTING_CONTAINERS="$("${COMPOSE[@]}" ps -q 2>/dev/null || true)"
if [[ -n "$EXISTING_CONTAINERS" ]]; then
  echo "Found a partial FlowlessHub first deployment; resuming without deleting containers or volumes."
fi

# Nginx is not changed here. Caddy publishes only loopback ports 3032 (web) and 5052 (API).
if [[ -e "$CADDY_DIR/Caddyfile" ]]; then
  if ! cmp -s "$ROOT/deploy/vps/Caddyfile.blue" "$CADDY_DIR/Caddyfile"; then
    echo "Existing Caddyfile differs from the initial blue config. Inspect it; refusing to overwrite runtime state." >&2
    exit 1
  fi
else
  CADDY_TMP="$(mktemp "$CADDY_DIR/Caddyfile.XXXXXX")"
  cp "$ROOT/deploy/vps/Caddyfile.blue" "$CADDY_TMP"
  chmod 644 "$CADDY_TMP"
  mv "$CADDY_TMP" "$CADDY_DIR/Caddyfile"
fi

echo "Pulling release images and pinned infrastructure images..."
"${COMPOSE[@]}" pull postgres pgbouncer edge api-blue web-blue worker migrate

echo "Starting only FlowlessHub PostgreSQL and PgBouncer..."
"${COMPOSE[@]}" up -d postgres pgbouncer

DB_USER="$(sed -n 's/^FLOWLESSHUB_DB_USER=//p' "$ENV_FILE" | tail -1)"
DB_NAME="$(sed -n 's/^FLOWLESSHUB_DB_NAME=//p' "$ENV_FILE" | tail -1)"
ready=0
for ((attempt = 1; attempt <= 60; attempt++)); do
  if "${COMPOSE[@]}" exec -T postgres pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1 && \
     "${COMPOSE[@]}" exec -T pgbouncer sh -ec "PGPASSWORD=\"\$DB_PASSWORD\" psql -h 127.0.0.1 -p 6432 -U \"\$DB_USER\" -d \"\$DB_NAME\" -v ON_ERROR_STOP=1 -c \"SELECT 1\" >/dev/null" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
if (( ready == 0 )); then
  "${COMPOSE[@]}" ps
  "${COMPOSE[@]}" logs --tail=100 postgres pgbouncer
  echo "FlowlessHub database did not become ready. Existing FlowlessHub data was preserved." >&2
  exit 1
fi

# This is a dedicated FlowlessHub database. Migrations are versioned and safe to rerun.
"${COMPOSE[@]}" --profile tools run --rm migrate

echo "Starting blue API/web, the single worker, and the internal Caddy edge..."
"${COMPOSE[@]}" --profile blue up -d api-blue web-blue worker edge

worker_ready=0
for ((attempt = 1; attempt <= 20; attempt++)); do
  worker_ids="$("${COMPOSE[@]}" ps -q worker)"
  worker_count="$(printf '%s\n' "$worker_ids" | awk 'NF { n++ } END { print n + 0 }')"
  if [[ "$worker_count" == "1" ]]; then
    worker_id="$(printf '%s\n' "$worker_ids" | head -n 1)"
    worker_running="$(docker inspect --format '{{.State.Running}}' "$worker_id")"
    worker_log="$("${COMPOSE[@]}" logs --no-color --tail=80 worker 2>/dev/null || true)"
    if [[ "$worker_running" == "true" ]] && grep -Fq 'River worker started' <<< "$worker_log"; then
      worker_ready=1
      break
    fi
  fi
  sleep 1
done
if (( worker_ready == 0 )); then
  "${COMPOSE[@]}" ps
  "${COMPOSE[@]}" logs --tail=100 worker
  echo "The single River worker did not reach its expected startup state." >&2
  echo "The FlowlessHub deployment remains resumable; Nginx and Petshop were not changed." >&2
  exit 1
fi

# Candidate checks use an ephemeral curl container on the private Compose network.
docker pull curlimages/curl:8.12.1
ready=0
for ((attempt = 1; attempt <= 40; attempt++)); do
  if docker run --rm --network flowlesshub-vps-edge curlimages/curl:8.12.1 -fsS --max-time 3 http://api-blue:5050/readyz >/dev/null 2>&1 && \
     docker run --rm --network flowlesshub-vps-edge curlimages/curl:8.12.1 -fsS --max-time 5 http://web-blue:3000/ >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 3
done
if (( ready == 0 )); then
  "${COMPOSE[@]}" ps
  "${COMPOSE[@]}" logs --tail=100 api-blue web-blue worker edge
  echo "Blue application workloads did not become healthy. Nginx has not been changed; rerun after diagnosis." >&2
  exit 1
fi

"${COMPOSE[@]}" exec -T edge caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
edge_ready=0
for ((attempt = 1; attempt <= 20; attempt++)); do
  if curl -fsS --max-time 3 http://127.0.0.1:5052/readyz >/dev/null 2>&1 && \
     curl -fsS --max-time 5 http://127.0.0.1:3032/ >/dev/null 2>&1; then
    edge_ready=1
    break
  fi
  sleep 1
done
if (( edge_ready == 0 )); then
  "${COMPOSE[@]}" logs --tail=100 edge
  echo "Caddy loopback upstream probes failed; Nginx has not been changed. Inspect and rerun safely." >&2
  exit 1
fi

STATE_TMP="$(mktemp "$RUNTIME_DIR/active-color.XXXXXX")"
printf 'blue\n' > "$STATE_TMP"
chmod 600 "$STATE_TMP"
mv "$STATE_TMP" "$RUNTIME_DIR/active-color"

"${COMPOSE[@]}" ps
printf '\nInitial FlowlessHub blue deployment passed.\n'
printf 'Caddy is private on 127.0.0.1:3032 (web) and 127.0.0.1:5052 (API). Host Nginx :80/:443 was not modified.\n'
printf 'Next: configure DNS, issue the certificate, and install the Nginx site from the runbook.\n'
