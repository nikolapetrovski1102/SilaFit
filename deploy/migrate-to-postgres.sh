#!/usr/bin/env bash
###############################################################################
# One-time move of the production database from SQL Server to PostgreSQL.
#
#   ./migrate-to-postgres.sh rehearse
#       Non-destructive dry run next to the live system. Copies the live
#       SQL Server data (read-only) into a throwaway database silendb_rehearsal,
#       verifies it, applies constraints + functions, and starts a second API on
#       127.0.0.1:5011 against it (no emails, no pushes) to test with. The live
#       API keeps running on SQL Server the whole time. Can run from a staging
#       copy of the repo; it always reads the live .env from $LIVE_DIR.
#
#   ./migrate-to-postgres.sh rehearse-clean
#       Stops the rehearsal API and drops silendb_rehearsal.
#
#   ./migrate-to-postgres.sh cutover
#       The real move, run from /opt/silen/deploy after the new code is synced.
#       Stops the API and the cron jobs, takes a last SQL Server backup, copies
#       everything into silendb, verifies every table (aborts and restarts the
#       old API on any mismatch), applies constraints + functions, stops SQL
#       Server (kept, not deleted) and runs ./deploy.sh to bring the API, cron
#       jobs and the new pg_dump backups up on PostgreSQL.
#
#   ./migrate-to-postgres.sh rollback
#       Puts the pre-migration API image back on SQL Server. Anything written
#       to PostgreSQL after the cutover is NOT carried back.
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIVE_DIR="${LIVE_DIR:-/opt/silen/deploy}"
ENV_FILE="$LIVE_DIR/.env"
ROLLBACK_DIR=/opt/silen/rollback-sqlserver
BACKUP_DIR=/opt/silen/backups
NETWORK=silenfit_default
REHEARSAL_DB=silendb_rehearsal
TOOL_CRONS="silen-monthly-review silen-notification-publish silen-subscription-sync silen-weekly-plan-generation silen-db-backup"

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m    ✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m    ! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m    ✗ %s\033[0m\n' "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root."
[ -s "$ENV_FILE" ] || die "$ENV_FILE not found."
MODE="${1:-}"

set -a; source "$ENV_FILE"; set +a
if [ -z "${POSTGRES_PASSWORD:-}" ]; then
  POSTGRES_PASSWORD="$(openssl rand -hex 24)"
  ( umask 077; printf 'POSTGRES_PASSWORD=%s\n' "$POSTGRES_PASSWORD" >> "$ENV_FILE" )
  export POSTGRES_PASSWORD
  ok "Generated POSTGRES_PASSWORD -> $ENV_FILE"
fi

compose() { docker compose -f "$SCRIPT_DIR/docker-compose.yml" --env-file "$ENV_FILE" "$@"; }
psql_db() { local db="$1"; shift; docker exec -i silen-postgres psql -U postgres -d "$db" -X -q -v ON_ERROR_STOP=1 "$@"; }
pg_value() { docker exec -i silen-postgres psql -U postgres -d "$1" -X -q -At -v ON_ERROR_STOP=1 -c "$2"; }
running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }
exists() { docker ps -a --format '{{.Names}}' | grep -qx "$1"; }

wait_healthy() {  # wait_healthy <container> <tries>
  local status=""
  for _ in $(seq 1 "$2"); do
    status="$(docker inspect -f '{{.State.Health.Status}}' "$1" 2>/dev/null || echo starting)"
    [ "$status" = "healthy" ] && return 0
    sleep 3
  done
  docker logs --tail 40 "$1"; die "$1 did not become healthy"
}

start_postgres() {
  log "Starting PostgreSQL"
  compose up -d silen-postgres
  wait_healthy silen-postgres 60
  ok "silen-postgres healthy ($(pg_value postgres 'SHOW server_version'))"
}

check_disk() {
  local free_gb
  free_gb="$(df -BG --output=avail / | tail -1 | tr -dc 0-9)"
  [ "$free_gb" -ge "$1" ] || die "Only ${free_gb}G free on /, need ${1}G. Try: docker builder prune -f"
  ok "${free_gb}G free on /"
}

# Bare tables -> data copy -> verify -> constraints, functions, grants -> ANALYZE.
# Returns 1 when verification fails, 2 on any other error. Every step checks its
# own status because callers use `copy_into ... ||`, which switches set -e off.
copy_into() {  # copy_into <db>
  local db="$1"
  local psql="docker exec -i silen-postgres psql -U postgres -d $db"
  log "Creating tables in $db"
  PSQL="$psql" "$REPO_ROOT/database/apply.sh" --until=0001 || return 2

  log "Building the copy tool"
  compose --profile legacy build silen-migrate-to-postgres >/dev/null || return 2
  log "Copying SQL Server -> $db"
  TARGET_DB="$db" compose --profile legacy run --rm --no-deps -T silen-migrate-to-postgres copy || return 2
  log "Verifying every table (row counts + per-column fingerprints)"
  TARGET_DB="$db" compose --profile legacy run --rm --no-deps -T silen-migrate-to-postgres verify || return 1

  log "Applying constraints, functions and grants"
  PSQL="$psql" "$REPO_ROOT/database/apply.sh" || return 2
  echo "ALTER ROLE silen_app WITH LOGIN PASSWORD :'pw';" | psql_db "$db" -v pw="$APP_DB_PASSWORD" || return 2
  log "ANALYZE"
  docker exec silen-postgres vacuumdb -U postgres -d "$db" --analyze-only --quiet || return 2
  ok "$db ready: $(pg_value "$db" "SELECT pg_size_pretty(pg_database_size(current_database()))")"
}

# The live API container's environment, with overrides, as a docker --env-file.
api_env_file() {  # api_env_file <source container or inspect json> <out> [KEY=VALUE ...]
  local src="$1" out="$2"; shift 2
  local inspect="$src"
  if [ ! -f "$src" ]; then inspect="$(mktemp)"; docker inspect "$src" > "$inspect"; fi
  python3 - "$inspect" "$out" "$@" <<'PY'
import json, sys
env = dict(e.split("=", 1) for e in json.load(open(sys.argv[1]))[0]["Config"]["Env"])
for kv in sys.argv[3:]:
    k, v = kv.split("=", 1)
    env[k] = v
with open(sys.argv[2], "w") as f:
    for k, v in env.items():
        f.write(f"{k}={v}\n")
PY
  chmod 600 "$out"
  [ -f "$src" ] || rm -f "$inspect"
}

pause_crons() {
  mkdir -p /etc/silen/cron-paused
  for c in $TOOL_CRONS; do
    [ -f "/etc/cron.d/$c" ] && mv "/etc/cron.d/$c" "/etc/silen/cron-paused/$c"
  done
  ok "cron jobs paused (/etc/silen/cron-paused)"
  for _ in $(seq 1 60); do
    docker ps --format '{{.Names}}' | grep -qE '^silenfit-silen-(notification|monthly|weekly|subscription)|^silen-(notification-publish|monthly-review|weekly-plan-generation|subscription-sync)' || { ok "no tool container running"; return 0; }
    sleep 5
  done
  die "a cron tool container is still running after 5 minutes; check docker ps"
}

restore_crons() {
  for c in $TOOL_CRONS; do
    [ -f "/etc/silen/cron-paused/$c" ] && mv "/etc/silen/cron-paused/$c" "/etc/cron.d/$c"
  done
  ok "cron jobs restored"
}

sqlserver_backup() {  # sqlserver_backup <file name>
  local inner=/var/opt/mssql/backup/nightly
  docker exec silen-sqlserver mkdir -p "$inner"
  docker exec -e SAPW="$SA_PASSWORD" -e F="$inner/$1" silen-sqlserver /bin/bash -c '
    /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SAPW" -C -b -Q "BACKUP DATABASE [SilenDb] TO DISK = N'"'"'$F'"'"' WITH COMPRESSION, CHECKSUM, MAXTRANSFERSIZE = 4194304, INIT"'
  docker cp "silen-sqlserver:$inner/$1" "$BACKUP_DIR/$1"
  docker exec silen-sqlserver rm -f "$inner/$1"
  chmod 600 "$BACKUP_DIR/$1"
  ok "$BACKUP_DIR/$1 ($(du -h "$BACKUP_DIR/$1" | cut -f1))"
}

case "$MODE" in
# -----------------------------------------------------------------------------
rehearse)
  running silen-sqlserver || die "silen-sqlserver is not running."
  running silen-api || die "silen-api is not running (the rehearsal copies its configuration)."
  check_disk 3
  start_postgres

  log "Recreating $REHEARSAL_DB"
  docker exec silen-postgres dropdb -U postgres --if-exists --force "$REHEARSAL_DB"
  docker exec silen-postgres createdb -U postgres "$REHEARSAL_DB"
  rc=0; copy_into "$REHEARSAL_DB" || rc=$?
  [ "$rc" -eq 2 ] && die "rehearsal failed (see above)"
  [ "$rc" -eq 1 ] && warn "verify reported differences - expected only in tables the live app wrote to during the copy"

  log "Starting the rehearsal API on 127.0.0.1:5011"
  docker rm -f silen-api-rehearsal >/dev/null 2>&1 || true
  docker build -q -t silen-api:pg-rehearsal -f "$REPO_ROOT/backend/Dockerfile" "$REPO_ROOT/backend" >/dev/null
  api_env_file silen-api "$SCRIPT_DIR/.rehearsal.env" \
    "ConnectionStrings__SilenDb=Host=silen-postgres;Port=5432;Database=$REHEARSAL_DB;Username=silen_app;Password=$APP_DB_PASSWORD;Maximum Pool Size=20" \
    "Smtp__Host=" "Push__Enabled=false" "NotificationPublish__RunInApi=false"
  # A throwaway copy of the uploads, so nothing the rehearsal writes reaches the live folder.
  rm -rf /tmp/silen-rehearsal-uploads
  cp -a "$LIVE_DIR/uploads" /tmp/silen-rehearsal-uploads
  docker run -d --name silen-api-rehearsal --network "$NETWORK" -p 127.0.0.1:5011:8080 \
    --env-file "$SCRIPT_DIR/.rehearsal.env" -v "$LIVE_DIR/secrets:/secrets:ro" \
    -v /tmp/silen-rehearsal-uploads:/app/uploads --memory 768m \
    silen-api:pg-rehearsal >/dev/null
  rm -f "$SCRIPT_DIR/.rehearsal.env"
  for _ in $(seq 1 40); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:5011/health/ready || true)" = "200" ] && break
    sleep 3
  done
  curl -fsS http://127.0.0.1:5011/health/ready >/dev/null || { docker logs --tail 60 silen-api-rehearsal; die "rehearsal API is not healthy"; }
  ok "rehearsal API healthy on 127.0.0.1:5011 (SMTP and push off)"
  echo
  echo "  Try it from your machine:  ssh -L 5011:127.0.0.1:5011 root@<server>   then http://localhost:5011"
  echo "  Clean up afterwards:       $0 rehearse-clean"
  ;;
# -----------------------------------------------------------------------------
rehearse-clean)
  docker rm -f silen-api-rehearsal >/dev/null 2>&1 || true
  running silen-postgres && docker exec silen-postgres dropdb -U postgres --if-exists --force "$REHEARSAL_DB"
  docker image rm silen-api:pg-rehearsal >/dev/null 2>&1 || true
  rm -rf /tmp/silen-rehearsal-uploads
  ok "rehearsal API and $REHEARSAL_DB removed (silen-postgres itself stays for the cutover)"
  ;;
# -----------------------------------------------------------------------------
cutover)
  [ "$SCRIPT_DIR" = "$LIVE_DIR" ] || die "Run cutover from $LIVE_DIR (after syncing the new code there)."
  running silen-sqlserver || die "silen-sqlserver is not running."
  exists silen-api || die "silen-api does not exist."
  if running silen-postgres && [ "$(pg_value silendb "SELECT to_regclass('public.schema_migrations') IS NOT NULL AND EXISTS (SELECT 1 FROM public.schema_migrations WHERE filename > '0001')" 2>/dev/null || true)" = "t" ]; then
    die "silendb is already migrated. Use ./deploy.sh for normal deploys."
  fi
  start_postgres
  docker rm -f silen-api-rehearsal >/dev/null 2>&1 || true
  docker exec silen-postgres dropdb -U postgres --if-exists --force "$REHEARSAL_DB"
  check_disk 4

  log "Saving the SQL Server API for rollback"
  mkdir -p "$ROLLBACK_DIR"; chmod 700 "$ROLLBACK_DIR"
  docker inspect silen-api > "$ROLLBACK_DIR/silen-api.inspect.json"
  chmod 600 "$ROLLBACK_DIR/silen-api.inspect.json"
  docker tag "$(docker inspect -f '{{.Image}}' silen-api)" silen-api:pre-postgres
  ok "image silen-api:pre-postgres + $ROLLBACK_DIR/silen-api.inspect.json"

  log "Stopping writers"
  pause_crons
  docker stop silen-api >/dev/null
  ok "silen-api stopped - the app is offline from here until deploy.sh finishes"

  log "Last SQL Server backup"
  sqlserver_backup "SilenDb_premigration_$(date -u +%Y%m%d_%H%M%S).bak"

  log "Recreating silendb (empty)"
  docker exec silen-postgres dropdb -U postgres --if-exists --force silendb
  docker exec silen-postgres createdb -U postgres silendb
  if ! copy_into silendb; then
    warn "Copy or verification failed - putting the SQL Server API back."
    docker start silen-api >/dev/null
    restore_crons
    die "Cutover aborted. Nothing changed on SQL Server; the app is back on it. silendb holds the partial copy for inspection."
  fi

  log "Stopping SQL Server (container and volume are kept for rollback)"
  docker stop silen-sqlserver >/dev/null
  ok "silen-sqlserver stopped"

  log "Running deploy.sh (API, cron jobs and backups on PostgreSQL)"
  rm -rf /etc/silen/cron-paused
  "$SCRIPT_DIR/deploy.sh"

  log "First PostgreSQL backup"
  "$SCRIPT_DIR/run-db-backup.sh"
  echo
  ok "Cutover done. Rollback (loses writes made since): $0 rollback"
  warn "Copy the backup key off the server: scp root@<server>:/etc/silen/backup-age.key ~/silen-backup-age.key"
  ;;
# -----------------------------------------------------------------------------
rollback)
  [ -f "$ROLLBACK_DIR/silen-api.inspect.json" ] || die "No $ROLLBACK_DIR/silen-api.inspect.json - nothing to roll back to."
  docker image inspect silen-api:pre-postgres >/dev/null 2>&1 || die "Image silen-api:pre-postgres is gone."
  exists silen-sqlserver || die "silen-sqlserver container is gone."

  log "Stopping the PostgreSQL API and cron jobs"
  pause_crons
  docker rm -f silen-api >/dev/null 2>&1 || true

  log "Starting SQL Server"
  docker start silen-sqlserver >/dev/null
  wait_healthy silen-sqlserver 60

  log "Starting the pre-migration API"
  api_env_file "$ROLLBACK_DIR/silen-api.inspect.json" "$ROLLBACK_DIR/api.env"
  docker run -d --name silen-api --network "$NETWORK" -p "127.0.0.1:${API_PORT:-5010}:8080" \
    --env-file "$ROLLBACK_DIR/api.env" -v "$LIVE_DIR/secrets:/secrets:ro" -v "$LIVE_DIR/uploads:/app/uploads" \
    --memory "${API_MEM_LIMIT:-1024m}" --restart unless-stopped silen-api:pre-postgres >/dev/null
  rm -f "$ROLLBACK_DIR/api.env"
  ok "silen-api is back on SQL Server"
  warn "Cron jobs stay paused (they now target PostgreSQL). To finish the rollback, check out the"
  warn "pre-PostgreSQL commit, sync it to the server and run its deploy.sh."
  ;;
# -----------------------------------------------------------------------------
*)
  echo "Usage: $0 rehearse | rehearse-clean | cutover | rollback" >&2
  exit 2
  ;;
esac
