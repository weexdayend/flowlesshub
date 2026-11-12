#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.vps-runtime/.env"
COMPOSE_FILE="$ROOT/deploy/compose/vps.compose.yaml"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

"${COMPOSE[@]}" pull worker
"${COMPOSE[@]}" up -d --no-deps worker
"${COMPOSE[@]}" logs --tail=40 worker
printf 'The single River worker was updated. Do not run two worker containers for this deployment.\n'
