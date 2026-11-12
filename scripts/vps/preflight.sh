#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.vps-runtime/.env"
COMPOSE_FILE="$ROOT/deploy/compose/vps.compose.yaml"

for command in docker curl openssl awk df ss grep sed systemctl; do
  command -v "$command" >/dev/null 2>&1 || { echo "Missing required command: $command" >&2; exit 1; }
done

docker info >/dev/null
docker compose version >/dev/null
systemctl is-active --quiet nginx || { echo "Host Nginx must remain active; refusing deployment." >&2; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE. Follow the VPS runbook first." >&2; exit 1; }
[[ -f "$COMPOSE_FILE" ]] || { echo "Missing Compose file: $COMPOSE_FILE" >&2; exit 1; }

get_env() {
  local key="$1"
  sed -n "s/^${key}=//p" "$ENV_FILE" | tail -1
}

for key in FLOWLESSHUB_BLUE_RELEASE FLOWLESSHUB_GREEN_RELEASE FLOWLESSHUB_WORKER_RELEASE FLOWLESSHUB_MIGRATE_RELEASE; do
  value="$(get_env "$key")"
  [[ "$value" =~ ^sha-[0-9a-f]{40}$ ]] || { echo "$key must be a commit-addressed sha-<40-hex> image tag." >&2; exit 1; }
done
DB_PASSWORD="$(get_env FLOWLESSHUB_DB_PASSWORD)"
[[ "$DB_PASSWORD" =~ ^[0-9a-f]{64}$ ]] || { echo "FLOWLESSHUB_DB_PASSWORD must be a generated 64-hex-character password; do not use the example placeholder." >&2; exit 1; }
unset DB_PASSWORD

available_mib="$(awk '/MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)"
disk_available_kib="$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')"
disk_available_gib="$((disk_available_kib / 1024 / 1024))"

printf 'MemAvailable: %s MiB\n' "$available_mib"
printf 'Disk available: %s GiB\n' "$disk_available_gib"

if (( available_mib < 256 )); then
  echo "Only ${available_mib} MiB RAM is available. Refusing to add workloads." >&2
  exit 1
fi
if (( disk_available_gib < 5 )); then
  echo "Less than 5 GiB disk is available. Refusing deployment." >&2
  exit 1
fi

for port in 3032 5052; do
  if ss -ltn | awk '{print $4}' | grep -Eq "(^|:|\\])${port}$"; then
    echo "Host port ${port} is already occupied; inspect it before continuing." >&2
    exit 1
  fi
done

# Config validation only; this does not create, stop, or restart containers.
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --quiet

echo "Preflight passed. Nginx and existing Petshop containers were not modified."
