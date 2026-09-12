#!/usr/bin/env bash
# Applies schema, stored procedures, and seed data (in that order) against
# the SQL Server container started by docker-compose. Safe to re-run.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTAINER_NAME="silen-sqlserver"
SA_PASSWORD="Silen_Dev_Passw0rd!"
SQLCMD="/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P ${SA_PASSWORD} -C -b"

run_sql_file() {
    local host_path="$1"
    local container_path="/tmp/$(basename "$host_path")"
    docker cp "$host_path" "${CONTAINER_NAME}:${container_path}"
    echo "-> $(basename "$host_path")"
    docker exec "$CONTAINER_NAME" bash -c "${SQLCMD} -i ${container_path}"
}

echo "Waiting for ${CONTAINER_NAME} to be healthy..."
for _ in $(seq 1 30); do
    status="$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "missing")"
    [ "$status" = "healthy" ] && break
    sleep 2
done

echo "== Schema =="
for f in "$ROOT_DIR"/database/schema/*.sql; do run_sql_file "$f"; done

echo "== Procedures =="
for f in "$ROOT_DIR"/database/procedures/*.sql; do run_sql_file "$f"; done

echo "== Seed data =="
for f in "$ROOT_DIR"/database/seed/*.sql; do run_sql_file "$f"; done

echo "Database deployed."
