#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNTIME_DIR="$ROOT/.vps-runtime"
ENV_FILE="$RUNTIME_DIR/.env"
COMPOSE_FILE="$ROOT/deploy/compose/vps.compose.yaml"
BACKUP_DIR="$RUNTIME_DIR/backups"
POSTGRES_IMAGE="postgres:17.11-alpine"
MIN_FREE_BYTES=$((5 * 1024 * 1024 * 1024))

for command in docker flock sha256sum df awk stat date mktemp git tr; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
[[ "$(stat -c '%a' "$ENV_FILE")" == "600" ]] || {
  echo "Runtime .env must have mode 600." >&2
  exit 1
}
git -C "$ROOT" check-ignore -q "$ENV_FILE" || {
  echo "Runtime .env is not Git-ignored; refusing backup." >&2
  exit 1
}

docker image inspect "$POSTGRES_IMAGE" >/dev/null 2>&1 || {
  echo "Required local validation image is missing: $POSTGRES_IMAGE. Refusing an implicit pull." >&2
  exit 1
}

mkdir -p "$BACKUP_DIR"
chmod 700 "$RUNTIME_DIR" "$BACKUP_DIR"

# Serialize backup and restore drills without acquiring or modifying deployment state.
exec 9>"$RUNTIME_DIR/backup.lock"
flock -n 9 || {
  echo "Another FlowlessHub backup/restore drill is running." >&2
  exit 1
}

# Keep even the archive verifier bounded on the small production host.
# shellcheck disable=SC2016 # AWK owns the memory fields in this single-quoted program.
AVAILABLE_MIB="$(awk '/MemAvailable:/ {printf "%d", $2/1024}' /proc/meminfo)"
# shellcheck disable=SC2016 # AWK owns the memory field in this single-quoted program.
SWAP_FREE_MIB="$(awk '/SwapFree:/ {printf "%d", $2/1024}' /proc/meminfo)"
if (( AVAILABLE_MIB < 256 )); then
  echo "Backup refused: MemAvailable=${AVAILABLE_MIB} MiB; minimum=256 MiB." >&2
  exit 1
fi
if (( SWAP_FREE_MIB < 128 )); then
  echo "Backup refused: SwapFree=${SWAP_FREE_MIB} MiB; minimum=128 MiB." >&2
  exit 1
fi

COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
POSTGRES_ID="$("${COMPOSE[@]}" ps -q postgres)"
[[ -n "$POSTGRES_ID" ]] || { echo "FlowlessHub PostgreSQL container is missing." >&2; exit 1; }
[[ "$(docker inspect --format '{{.State.Running}}' "$POSTGRES_ID")" == "true" ]] || {
  echo "FlowlessHub PostgreSQL is not running." >&2
  exit 1
}
[[ "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$POSTGRES_ID")" == "healthy" ]] || {
  echo "FlowlessHub PostgreSQL is not healthy." >&2
  exit 1
}

# shellcheck disable=SC2016 # Expanded by the shell inside the PostgreSQL container.
DB_NAME="$("${COMPOSE[@]}" exec -T postgres sh -ec 'printf "%s" "$POSTGRES_DB"')"
# shellcheck disable=SC2016 # Expanded by the shell inside the PostgreSQL container.
PG_VERSION="$("${COMPOSE[@]}" exec -T postgres sh -ec 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SHOW server_version"')"
# shellcheck disable=SC2016 # Expanded by the shell inside the PostgreSQL container.
DB_SIZE_BYTES="$("${COMPOSE[@]}" exec -T postgres sh -ec 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT pg_database_size(current_database())"')"
# shellcheck disable=SC2016 # Expanded by the shell inside the PostgreSQL container.
USER_SCHEMA_COUNT="$("${COMPOSE[@]}" exec -T postgres sh -ec 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT count(*) FROM pg_namespace WHERE nspname::text NOT LIKE (chr(112)||chr(103)||chr(95)||chr(37)) AND nspname::text <> (chr(105)||chr(110)||chr(102)||chr(111)||chr(114)||chr(109)||chr(97)||chr(116)||chr(105)||chr(111)||chr(110)||chr(95)||chr(115)||chr(99)||chr(104)||chr(101)||chr(109)||chr(97))"')"
# shellcheck disable=SC2016 # Expanded by the shell inside the PostgreSQL container.
USER_RELATION_COUNT="$("${COMPOSE[@]}" exec -T postgres sh -ec 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname::text NOT LIKE (chr(112)||chr(103)||chr(95)||chr(37)) AND n.nspname::text <> (chr(105)||chr(110)||chr(102)||chr(111)||chr(114)||chr(109)||chr(97)||chr(116)||chr(105)||chr(111)||chr(110)||chr(95)||chr(115)||chr(99)||chr(104)||chr(101)||chr(109)||chr(97)) AND c.relkind::text IN (chr(114),chr(112),chr(118),chr(109),chr(83),chr(102))"')"
ACTIVE_COLOR="$(tr -d '\r\n' < "$RUNTIME_DIR/active-color")"
SOURCE_COMMIT="$(git -C "$ROOT" rev-parse HEAD)"

[[ "$DB_NAME" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "Unexpected database name format; refusing to write manifest." >&2; exit 1; }
[[ "$PG_VERSION" =~ ^17\. ]] || { echo "Expected PostgreSQL 17, found $PG_VERSION." >&2; exit 1; }
[[ "$DB_SIZE_BYTES" =~ ^[0-9]+$ ]] || { echo "Invalid database size result." >&2; exit 1; }
[[ "$USER_SCHEMA_COUNT" =~ ^[0-9]+$ ]] || { echo "Invalid schema count result." >&2; exit 1; }
[[ "$USER_RELATION_COUNT" =~ ^[0-9]+$ ]] || { echo "Invalid relation count result." >&2; exit 1; }
[[ "$ACTIVE_COLOR" == "blue" || "$ACTIVE_COLOR" == "green" ]] || {
  echo "Invalid active-color state: $ACTIVE_COLOR" >&2
  exit 1
}
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid repository HEAD." >&2; exit 1; }

# shellcheck disable=SC2016 # AWK owns the positional field in this single-quoted program.
AVAILABLE_BYTES="$(df -PB1 "$BACKUP_DIR" | awk 'NR == 2 {print $4}')"
[[ "$AVAILABLE_BYTES" =~ ^[0-9]+$ ]] || { echo "Unable to determine available disk space." >&2; exit 1; }
REQUIRED_BYTES=$((MIN_FREE_BYTES + DB_SIZE_BYTES * 2))
if (( AVAILABLE_BYTES < REQUIRED_BYTES )); then
  echo "Insufficient disk space: available=${AVAILABLE_BYTES}, required=${REQUIRED_BYTES}." >&2
  exit 1
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BASE="flowlesshub-${STAMP}.dump"
OUT="$BACKUP_DIR/$BASE"
SHA_OUT="$OUT.sha256"
MANIFEST_OUT="$OUT.manifest"
[[ ! -e "$OUT" && ! -e "$SHA_OUT" && ! -e "$MANIFEST_OUT" ]] || {
  echo "Backup artifact already exists for timestamp $STAMP." >&2
  exit 1
}

TMP_DUMP="$(mktemp "$BACKUP_DIR/.${BASE}.partial.XXXXXX")"
TMP_SHA="$(mktemp "$BACKUP_DIR/.${BASE}.sha256.XXXXXX")"
TMP_MANIFEST="$(mktemp "$BACKUP_DIR/.${BASE}.manifest.XXXXXX")"
COMPLETE=0

cleanup() {
  status=$?
  trap - EXIT
  rm -f -- "$TMP_DUMP" "$TMP_SHA" "$TMP_MANIFEST"
  if (( COMPLETE == 0 )); then
    rm -f -- "$OUT" "$SHA_OUT" "$MANIFEST_OUT"
  fi
  exit "$status"
}
trap cleanup EXIT

# shellcheck disable=SC2016 # Expanded by the shell inside the PostgreSQL container.
"${COMPOSE[@]}" exec -T postgres sh -ec \
  'exec pg_dump --format=custom --no-owner --no-privileges --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"' \
  > "$TMP_DUMP"

[[ -s "$TMP_DUMP" ]] || { echo "pg_dump produced an empty archive." >&2; exit 1; }
chmod 600 "$TMP_DUMP"

# Read the archive catalog in a network-isolated, resource-limited helper container.
docker run --rm \
  --network none \
  --memory 128m \
  --memory-swap 128m \
  --cpus 0.25 \
  --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m \
  --mount "type=bind,src=$BACKUP_DIR,dst=/backups,readonly" \
  "$POSTGRES_IMAGE" \
  pg_restore --list "/backups/$(basename "$TMP_DUMP")" >/dev/null

# shellcheck disable=SC2016 # AWK owns the positional field in this single-quoted program.
BACKUP_SHA256="$(sha256sum "$TMP_DUMP" | awk '{print $1}')"
[[ "$BACKUP_SHA256" =~ ^[0-9a-f]{64}$ ]] || { echo "Unable to calculate backup checksum." >&2; exit 1; }
printf '%s  %s\n' "$BACKUP_SHA256" "$BASE" > "$TMP_SHA"

cat > "$TMP_MANIFEST" <<MANIFEST
format=postgres-custom
created_at_utc=$STAMP
source_commit=$SOURCE_COMMIT
active_color=$ACTIVE_COLOR
database_name=$DB_NAME
postgres_server_version=$PG_VERSION
database_size_bytes=$DB_SIZE_BYTES
user_schema_count=$USER_SCHEMA_COUNT
user_relation_count=$USER_RELATION_COUNT
backup_file=$BASE
backup_sha256=$BACKUP_SHA256
MANIFEST

chmod 600 "$TMP_SHA" "$TMP_MANIFEST"
mv -- "$TMP_DUMP" "$OUT"
mv -- "$TMP_SHA" "$SHA_OUT"
mv -- "$TMP_MANIFEST" "$MANIFEST_OUT"

(
  cd "$BACKUP_DIR"
  sha256sum --check "$(basename "$SHA_OUT")" >/dev/null
)

# Re-check the published archive and sidecars before declaring success.
"$ROOT/scripts/vps/verify-backup.sh" "$OUT"
COMPLETE=1

printf 'Database backup completed and verified.\n'
printf 'Archive: %s\n' "$OUT"
printf 'SHA-256: %s\n' "$BACKUP_SHA256"
printf 'Archive bytes: %s\n' "$(stat -c '%s' "$OUT")"
printf 'Manifest: %s\n' "$MANIFEST_OUT"
printf 'Copy the archive and both sidecars off-host, then verify their checksums.\n'
