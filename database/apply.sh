#!/usr/bin/env bash
###############################################################################
# Brings a PostgreSQL database up to date with this directory:
#
#   1. roles      silen_owner (NOLOGIN) owns the database, schema, tables and
#                 functions; silen_app (the API and scheduled tools) only gets
#                 USAGE on dbo + EXECUTE on its functions. The functions are
#                 SECURITY DEFINER, so silen_app reaches the tables through them
#                 and nothing else - the same least-privilege model the SQL
#                 Server login had (EXECUTE on dbo, ownership chaining).
#   2. migrations database/migrations/*.sql, each applied once, in order, in its
#                 own transaction, recorded in public.schema_migrations.
#      seed       database/seed/*.sql, only when the database had no migrations
#                 yet (a brand-new install), loaded right after migration
#                 $SEED_AFTER. The seed is the catalog as of that baseline, so the
#                 later catalog migrations (new splits, meals, fixes) run on top of
#                 it exactly as they did in production. Production data never
#                 gets re-seeded.
#   3. functions  every dbo function except the 0001 helpers is dropped and
#                 database/functions/*.sql recreated in one transaction, so a
#                 removed or re-signatured function never lingers as an overload.
#
# Runs psql through $PSQL, which must connect as a superuser to the target
# database and read SQL from stdin. Defaults to the local/production container:
#   PSQL="docker exec -i silen-postgres psql -U postgres -d silendb"
#
# Usage:
#   database/apply.sh                  # everything
#   database/apply.sh --until=0001     # migrations up to 0001 only, no functions/seed
#                                      # (the SQL Server data copy loads in between)
###############################################################################
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL="${PSQL:-docker exec -i silen-postgres psql -U postgres -d silendb}"
# The migration the seed snapshot sits on: schema up to here, catalog data after.
SEED_AFTER=0002
UNTIL=""
for arg in "$@"; do
  case "$arg" in
    --until=*) UNTIL="${arg#--until=}" ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

psql_run() { $PSQL -X -q -v ON_ERROR_STOP=1 "$@"; }
psql_value() { $PSQL -X -q -At -v ON_ERROR_STOP=1 -c "$1"; }

# ---- 1. roles ----------------------------------------------------------------
psql_run <<'SQL'
SET client_min_messages = warning;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'silen_owner') THEN
        CREATE ROLE silen_owner NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'silen_app') THEN
        CREATE ROLE silen_app LOGIN;
    END IF;
    EXECUTE format('ALTER DATABASE %I OWNER TO silen_owner', current_database());
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO silen_app', current_database());
END $$;
CREATE TABLE IF NOT EXISTS public.schema_migrations (
    filename text PRIMARY KEY,
    appliedatutc timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'UTC')
);
ALTER TABLE public.schema_migrations OWNER TO silen_owner;
SQL

fresh="$(psql_value "SELECT NOT EXISTS (SELECT 1 FROM public.schema_migrations)")"

# ---- 2. migrations -----------------------------------------------------------
for f in "$DIR"/migrations/*.sql; do
  name="$(basename "$f")"
  # Numeric compare on the NNNN prefix: [[ > ]] follows the locale's collation,
  # which ignores punctuation in en_US.UTF-8 and so mis-orders the file names.
  if [ -n "$UNTIL" ] && (( 10#${name%%_*} > 10#$UNTIL )); then break; fi
  done_already="$(psql_value "SELECT EXISTS (SELECT 1 FROM public.schema_migrations WHERE filename = '$name')")"
  [ "$done_already" = "t" ] && continue
  echo "-> migration $name"
  {
    echo "BEGIN;"
    echo "SET LOCAL ROLE silen_owner;"
    echo "SET LOCAL search_path = dbo, public;"
    cat "$f"
    echo
    echo "INSERT INTO public.schema_migrations (filename) VALUES ('$name');"
    echo "COMMIT;"
  } | psql_run

  # ---- seed (brand-new install only) ----
  if [ "$fresh" = "t" ] && (( 10#${name%%_*} == 10#$SEED_AFTER )) \
     && compgen -G "$DIR/seed/*.sql" >/dev/null; then
    for s in "$DIR"/seed/*.sql; do
      echo "-> seed $(basename "$s")"
      { echo "BEGIN;"; echo "SET LOCAL ROLE silen_owner;"; cat "$s"; echo; echo "COMMIT;"; } | psql_run
    done
  fi
done

[ -n "$UNTIL" ] && { echo "Stopped after migrations up to $UNTIL."; exit 0; }

# ---- 3. functions ------------------------------------------------------------
echo "-> functions"
{
  echo "BEGIN;"
  echo "SET LOCAL ROLE silen_owner;"
  echo "SET LOCAL search_path = dbo, public;"
  cat <<'SQL'
DO $$
DECLARE f regprocedure;
BEGIN
    FOR f IN SELECT p.oid::regprocedure FROM pg_proc p
             WHERE p.pronamespace = 'dbo'::regnamespace AND p.proname NOT IN ('outcome_cursor', 'sysutcdatetime')
    LOOP
        EXECUTE format('DROP FUNCTION %s', f);
    END LOOP;
END $$;
SQL
  for f in "$DIR"/functions/*.sql; do cat "$f"; echo; done
  cat <<'SQL'
DO $$
DECLARE f regprocedure;
BEGIN
    FOR f IN SELECT p.oid::regprocedure FROM pg_proc p
             WHERE p.pronamespace = 'dbo'::regnamespace AND p.proname NOT IN ('outcome_cursor', 'sysutcdatetime')
    LOOP
        EXECUTE format('ALTER FUNCTION %s SECURITY DEFINER SET search_path = dbo, public, pg_temp', f);
    END LOOP;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA dbo FROM PUBLIC;
GRANT USAGE ON SCHEMA dbo TO silen_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA dbo TO silen_app;
COMMIT;
SQL
} | psql_run
echo "   $(psql_value "SELECT count(*) FROM pg_proc WHERE pronamespace = 'dbo'::regnamespace AND proname NOT IN ('outcome_cursor', 'sysutcdatetime')") functions"

echo "Database up to date."
