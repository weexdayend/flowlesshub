#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_DIR="$ROOT/.vps-runtime"
ENV_FILE="$RUNTIME_DIR/.env"
COMPOSE_FILE="$ROOT/deploy/compose/vps.compose.yaml"
BACKUP_DIR="$RUNTIME_DIR/backups"
POSTGRES_IMAGE="postgres:17.11-alpine"
MIN_AVAILABLE_MIB=512
MIN_SWAP_FREE_MIB=256
MIN_FREE_BYTES=$((5 * 1024 * 1024 * 1024))
CONTAINER_ID=""
CONTAINER_NAME=""

usage() {
  echo "Usage: $0 <path-to-flowlesshub-backup.dump>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
for command in docker flock awk df date realpath git stat openssl sed grep tr sleep; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

[[ -f "$ENV_FILE" ]] || { echo "Missing FlowlessHub runtime environment." >&2; exit 1; }
[[ "$(stat -c '%a' "$ENV_FILE")" == "600" ]] || { echo "Runtime .env must have mode 600." >&2; exit 1; }
git -C "$ROOT" check-ignore -q "$ENV_FILE" || { echo "Runtime .env is not Git-ignored." >&2; exit 1; }

exec 9>"$RUNTIME_DIR/backup.lock"
flock -n 9 || {
  echo "Another FlowlessHub backup/restore drill is running." >&2
  exit 1
}

# Resolve the target artifact and perform host-capacity guards before running even
# the small pg_restore --list verifier container.
BACKUP_PATH="$(realpath -e -- "$1")"
BACKUP_DIR_REAL="$(realpath -e -- "$BACKUP_DIR")"
BASE="$(basename "$BACKUP_PATH")"

# Require both RAM and swap headroom; the restore container itself cannot use swap.
# shellcheck disable=SC2016 # AWK owns the memory field in this single-quoted program.
AVAILABLE_MIB="$(awk '/MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)"
# shellcheck disable=SC2016 # AWK owns the memory field in this single-quoted program.
SWAP_FREE_MIB="$(awk '/SwapFree:/ {printf "%d", $2/1024}' /proc/meminfo)"
if (( AVAILABLE_MIB < MIN_AVAILABLE_MIB )); then
  echo "Restore drill refused: MemAvailable=${AVAILABLE_MIB} MiB; minimum=${MIN_AVAILABLE_MIB} MiB." >&2
  exit 1
fi
if (( SWAP_FREE_MIB < MIN_SWAP_FREE_MIB )); then
  echo "Restore drill refused: SwapFree=${SWAP_FREE_MIB} MiB; minimum=${MIN_SWAP_FREE_MIB} MiB." >&2
  exit 1
fi

BACKUP_BYTES="$(stat -c '%s' "$BACKUP_PATH")"
# shellcheck disable=SC2016 # AWK owns the disk field in this single-quoted program.
AVAILABLE_BYTES="$(df -PB1 "$BACKUP_DIR_REAL" | awk 'NR == 2 {print $4}')"
[[ "$BACKUP_BYTES" =~ ^[0-9]+$ && "$AVAILABLE_BYTES" =~ ^[0-9]+$ ]] || {
  echo "Unable to determine backup/disk size." >&2
  exit 1
}
REQUIRED_BYTES=$((MIN_FREE_BYTES + BACKUP_BYTES * 2))
if (( AVAILABLE_BYTES < REQUIRED_BYTES )); then
  echo "Restore drill refused: available disk=${AVAILABLE_BYTES}; required=${REQUIRED_BYTES}." >&2
  exit 1
fi

docker image inspect "$POSTGRES_IMAGE" >/dev/null 2>&1 || {
  echo "Required local image is missing: $POSTGRES_IMAGE. Refusing an implicit pull." >&2
  exit 1
}

# Validate the input and sidecars before starting the restore target.
"$ROOT/scripts/vps/verify-backup.sh" "$BACKUP_PATH"
MANIFEST_FILE="$BACKUP_PATH.manifest"
manifest_value() {
  local key="$1"
  # shellcheck disable=SC2016 # AWK owns the record fields in this single-quoted program.
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; found=1; exit} END {if (!found) exit 1}' "$MANIFEST_FILE"
}
EXPECTED_SCHEMA_COUNT="$(manifest_value user_schema_count)"
EXPECTED_RELATION_COUNT="$(manifest_value user_relation_count)"
EXPECTED_SOURCE_COMMIT="$(manifest_value source_commit)"

# A stale restore-drill container is a hard stop; never clean up unknown artifacts automatically.
EXISTING_DRILLS="$(docker ps -aq --filter label=com.flowlesshub.scope=restore-drill)"
[[ -z "$EXISTING_DRILLS" ]] || {
  echo "An existing restore-drill container was found. Inspect it before continuing:" >&2
  docker ps -a --filter label=com.flowlesshub.scope=restore-drill >&2
  exit 1
}

# Confirm production PostgreSQL is healthy before and after the isolated drill.
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
PROD_PG_ID="$("${COMPOSE[@]}" ps -q postgres)"
[[ -n "$PROD_PG_ID" ]] || { echo "Production PostgreSQL container is missing." >&2; exit 1; }
[[ "$(docker inspect --format '{{.State.Running}}' "$PROD_PG_ID")" == "true" ]] || {
  echo "Production PostgreSQL is not running." >&2
  exit 1
}
[[ "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$PROD_PG_ID")" == "healthy" ]] || {
  echo "Production PostgreSQL is not healthy." >&2
  exit 1
}
ACTIVE_BEFORE="$(tr -d '\r\n' < "$RUNTIME_DIR/active-color")"
[[ "$ACTIVE_BEFORE" == "blue" || "$ACTIVE_BEFORE" == "green" ]] || {
  echo "Invalid production active-color marker." >&2
  exit 1
}

# Recheck after archive verification and immediately before creating the restore target.
# shellcheck disable=SC2016 # AWK owns the memory field in this single-quoted program.
AVAILABLE_MIB="$(awk '/MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)"
# shellcheck disable=SC2016 # AWK owns the memory field in this single-quoted program.
SWAP_FREE_MIB="$(awk '/SwapFree:/ {printf "%d", $2/1024}' /proc/meminfo)"
if (( AVAILABLE_MIB < MIN_AVAILABLE_MIB || SWAP_FREE_MIB < MIN_SWAP_FREE_MIB )); then
  echo "Restore drill refused after verifier: MemAvailable=${AVAILABLE_MIB} MiB, SwapFree=${SWAP_FREE_MIB} MiB." >&2
  exit 1
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
CONTAINER_NAME="flowlesshub-restore-drill-${STAMP}-$$"
DRILL_PASSWORD="$(openssl rand -hex 24)"

cleanup() {
  status=$?
  trap - EXIT INT TERM

  local target="${CONTAINER_ID:-$CONTAINER_NAME}"
  if [[ -n "$target" ]] && docker inspect "$target" >/dev/null 2>&1; then
    local scope name
    scope="$(docker inspect --format '{{ index .Config.Labels "com.flowlesshub.scope" }}' "$target" 2>/dev/null || true)"
    name="$(docker inspect --format '{{.Name}}' "$target" 2>/dev/null | sed 's#^/##' || true)"
    if [[ "$scope" == "restore-drill" && "$name" == "$CONTAINER_NAME" ]]; then
      docker stop --time 10 "$target" >/dev/null || {
        echo "WARNING: failed to stop isolated restore container $CONTAINER_NAME." >&2
        status=1
      }
    else
      echo "WARNING: refusing cleanup of a container without the expected restore-drill label/name." >&2
      status=1
    fi
  fi

  if docker ps -aq --filter "name=^/${CONTAINER_NAME}$" | grep -q .; then
    echo "WARNING: isolated restore container remains; inspect only $CONTAINER_NAME." >&2
    status=1
  fi

  unset DRILL_PASSWORD
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

CONTAINER_ID="$(docker run --detach --rm \
  --name "$CONTAINER_NAME" \
  --label com.flowlesshub.scope=restore-drill \
  --label com.flowlesshub.repository=flowlesshub \
  --label com.flowlesshub.restore-source-commit="$EXPECTED_SOURCE_COMMIT" \
  --network none \
  --memory 256m \
  --memory-swap 256m \
  --cpus 0.50 \
  --pids-limit 64 \
  --env POSTGRES_USER=restore_drill \
  --env POSTGRES_PASSWORD="$DRILL_PASSWORD" \
  --env POSTGRES_DB=flowlesshub_restore \
  --mount "type=bind,src=$BACKUP_DIR_REAL,dst=/backups,readonly" \
  "$POSTGRES_IMAGE" \
  postgres -c shared_buffers=32MB -c max_connections=10 -c work_mem=1MB -c maintenance_work_mem=16MB -c max_wal_size=128MB -c min_wal_size=32MB)"
[[ -n "$CONTAINER_ID" ]] || { echo "Unable to start isolated restore container." >&2; exit 1; }

READY=0
for ((attempt = 1; attempt <= 30; attempt++)); do
  if ! docker inspect "$CONTAINER_ID" >/dev/null 2>&1; then
    echo "Restore container exited during PostgreSQL startup." >&2
    exit 1
  fi
  if docker exec "$CONTAINER_ID" pg_isready -U restore_drill -d flowlesshub_restore >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 2
done
[[ "$READY" == "1" ]] || { echo "Isolated PostgreSQL did not become ready." >&2; exit 1; }

RESTORE_STARTED_AT="$(date +%s)"
docker exec "$CONTAINER_ID" \
  pg_restore --exit-on-error --single-transaction --no-owner --no-privileges \
  --username=restore_drill \
  --dbname=flowlesshub_restore \
  "/backups/$BASE"
RESTORE_FINISHED_AT="$(date +%s)"

VALIDATION="$(docker exec "$CONTAINER_ID" psql -X -v ON_ERROR_STOP=1 \
  -U restore_drill -d flowlesshub_restore -AtF '|' \
  -c "SELECT current_database(), pg_database_size(current_database()), (SELECT count(*) FROM pg_namespace WHERE nspname::text NOT IN ('pg_catalog','information_schema') AND nspname::text NOT LIKE 'pg_%'), (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname::text NOT IN ('pg_catalog','information_schema') AND n.nspname::text NOT LIKE 'pg_%' AND c.relkind IN ('r','p','v','m','S','f')), (to_regnamespace('platform') IS NOT NULL)" )"
IFS='|' read -r RESTORED_DB RESTORED_BYTES RESTORED_SCHEMAS RESTORED_RELATIONS PLATFORM_PRESENT <<< "$VALIDATION"

[[ "$RESTORED_DB" == "flowlesshub_restore" ]] || { echo "Restored database identity mismatch." >&2; exit 1; }
if [[ ! "$RESTORED_BYTES" =~ ^[0-9]+$ ]] || (( RESTORED_BYTES <= 0 )); then
  echo "Restored database is empty or size query failed." >&2
  exit 1
fi
[[ "$RESTORED_SCHEMAS" == "$EXPECTED_SCHEMA_COUNT" ]] || {
  echo "Schema count mismatch: expected=$EXPECTED_SCHEMA_COUNT actual=$RESTORED_SCHEMAS" >&2
  exit 1
}
[[ "$RESTORED_RELATIONS" == "$EXPECTED_RELATION_COUNT" ]] || {
  echo "Relation count mismatch: expected=$EXPECTED_RELATION_COUNT actual=$RESTORED_RELATIONS" >&2
  exit 1
}
[[ "$PLATFORM_PRESENT" == "t" ]] || { echo "Expected platform schema is missing after restore." >&2; exit 1; }

[[ "$(docker inspect --format '{{.State.Running}}' "$PROD_PG_ID")" == "true" ]] || {
  echo "Production PostgreSQL state changed during restore drill." >&2
  exit 1
}
[[ "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$PROD_PG_ID")" == "healthy" ]] || {
  echo "Production PostgreSQL health changed during restore drill." >&2
  exit 1
}
[[ "$(tr -d '\r\n' < "$RUNTIME_DIR/active-color")" == "$ACTIVE_BEFORE" ]] || {
  echo "Production active-color changed during restore drill." >&2
  exit 1
}

ELAPSED_SECONDS=$((RESTORE_FINISHED_AT - RESTORE_STARTED_AT))
printf 'Isolated restore drill PASSED.\n'
printf 'Backup: %s\n' "$BASE"
printf 'Restore container: %s (network=none, memory=256MiB, swap=disabled, cpu=0.50)\n' "$CONTAINER_NAME"
printf 'Restored database: %s (%s bytes)\n' "$RESTORED_DB" "$RESTORED_BYTES"
printf 'User schemas: %s; user relations: %s; platform schema: %s\n' "$RESTORED_SCHEMAS" "$RESTORED_RELATIONS" "$PLATFORM_PRESENT"
printf 'Restore duration: %s seconds\n' "$ELAPSED_SECONDS"
printf 'Production PostgreSQL: still healthy; active color: %s\n' "$ACTIVE_BEFORE"
printf 'The disposable restore container will be stopped and auto-removed on exit.\n'
