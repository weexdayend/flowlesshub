#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.vps-runtime/.env"
COMPOSE_FILE="$ROOT/deploy/compose/vps.compose.yaml"
RUNTIME_DIR="$ROOT/.vps-runtime"
CADDY_DIR="$RUNTIME_DIR/caddy"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
"$ROOT/scripts/vps/preflight.sh"
mkdir -p "$CADDY_DIR" "$RUNTIME_DIR/backups"
chmod 700 "$RUNTIME_DIR" "$RUNTIME_DIR/backups"
chmod 755 "$CADDY_DIR"

if [[ -f "$RUNTIME_DIR/active-color" ]]; then
  echo "FlowlessHub already has an active-color marker. Use the release runbook, not first-install script." >&2
  exit 1
fi
if [[ -n "$("${COMPOSE[@]}" ps -q 2>/dev/null || true)" ]]; then
  echo "Compose already has FlowlessHub containers. Refusing first-install path." >&2
  exit 1
fi

# Nginx is not changed here. Caddy publishes only loopback ports 3032 (web) and 5052 (API).
cp "$ROOT/deploy/vps/Caddyfile.blue" "$CADDY_DIR/Caddyfile"
chmod 644 "$CADDY_DIR/Caddyfile"

echo "Pulling release images and pinned infrastructure images..."
"${COMPOSE[@]}" pull postgres pgbouncer edge api-blue web-blue worker migrate

echo "Starting only FlowlessHub PostgreSQL and PgBouncer..."
"${COMPOSE[@]}" up -d postgres pgbouncer

DB_USER="$(sed -n 's/^FLOWLESSHUB_DB_USER=//p' "$ENV_FILE" | tail -1)"
DB_NAME="$(sed -n 's/^FLOWLESSHUB_DB_NAME=//p' "$ENV_FILE" | tail -1)"
ready=0
for attempt in $(seq 1 60); do
  if "${COMPOSE[@]}" exec -T postgres pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1 && \
     "${COMPOSE[@]}" exec -T pgbouncer sh -ec 'PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -p 6432 -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "SELECT 1" >/dev/null' >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 2
done
if (( ready == 0 )); then
  "${COMPOSE[@]}" ps
  "${COMPOSE[@]}" logs --tail=100 postgres pgbouncer
  echo "FlowlessHub database did not become ready." >&2
  exit 1
fi

# This is a new dedicated FlowlessHub database. Migration runs once against PostgreSQL directly.
"${COMPOSE[@]}" --profile tools run --rm migrate

echo "Starting blue API/web, the single worker, and the internal Caddy edge..."
"${COMPOSE[@]}" --profile blue up -d api-blue web-blue worker edge

# Candidate checks use an ephemeral curl container on the private Compose network.
docker pull curlimages/curl:8.12.1
ready=0
for attempt in $(seq 1 40); do
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
  echo "Blue application workloads did not become healthy. Nginx has not been changed." >&2
  exit 1
fi

"${COMPOSE[@]}" exec -T edge caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
edge_ready=0
for attempt in $(seq 1 20); do
  if curl -fsS --max-time 3 http://127.0.0.1:5052/readyz >/dev/null 2>&1 && \
     curl -fsS --max-time 5 http://127.0.0.1:3032/ >/dev/null 2>&1; then
    edge_ready=1
    break
  fi
  sleep 1
done
if (( edge_ready == 0 )); then
  "${COMPOSE[@]}" logs --tail=100 edge
  echo "Caddy loopback upstream probes failed; Nginx has not been changed." >&2
  exit 1
fi
printf 'blue\n' > "$RUNTIME_DIR/active-color"
chmod 600 "$RUNTIME_DIR/active-color"

"${COMPOSE[@]}" ps
printf '\nInitial FlowlessHub blue deployment passed.\n'
printf 'Caddy is private on 127.0.0.1:3032 (web) and 127.0.0.1:5052 (API). Host Nginx :80/:443 was not modified.\n'
printf 'Next: configure DNS, issue the certificate, and install the Nginx site from the runbook.\n'
