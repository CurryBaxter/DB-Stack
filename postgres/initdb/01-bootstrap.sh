#!/bin/bash
set -euo pipefail

APP_DB_PASSWORD="$(cat /run/secrets/app_db_password)"
PGBOUNCER_AUTH_PASSWORD="$(cat /run/secrets/pgbouncer_auth_password)"
EXPORTER_PASSWORD="$(cat /run/secrets/postgres_exporter_password)"
REPLICATION_PASSWORD="$(cat /run/secrets/postgres_replication_password)"
REPLICATION_USER="${POSTGRES_REPLICATION_USER:-replicator}"
APP_DB_NAME="${APP_DB_NAME:?APP_DB_NAME is required}"
APP_DB_USER="${APP_DB_USER:?APP_DB_USER is required}"
PGBOUNCER_AUTH_USER="${PGBOUNCER_AUTH_USER:-pgbouncer_auth}"
EXPORTER_USER="${POSTGRES_EXPORTER_USER:-postgres_exporter}"

# ---------------------------------------------------------------------------
# Create roles and database
# Uses \gexec so psql variables work correctly (no DO $$ blocks needed)
# ---------------------------------------------------------------------------
psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname postgres \
  --set app_db_name="$APP_DB_NAME" \
  --set app_db_user="$APP_DB_USER" \
  --set app_db_password="$APP_DB_PASSWORD" \
  --set pgbouncer_auth_user="$PGBOUNCER_AUTH_USER" \
  --set pgbouncer_auth_password="$PGBOUNCER_AUTH_PASSWORD" \
  --set exporter_user="$EXPORTER_USER" \
  --set exporter_password="$EXPORTER_PASSWORD" \
  --set replication_user="$REPLICATION_USER" \
  --set replication_password="$REPLICATION_PASSWORD" <<'EOSQL'

-- App user
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'app_db_user', :'app_db_password')
  WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'app_db_user') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'app_db_user', :'app_db_password')
  WHERE EXISTS (SELECT FROM pg_roles WHERE rolname = :'app_db_user') \gexec

-- PgBouncer auth user
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'pgbouncer_auth_user', :'pgbouncer_auth_password')
  WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'pgbouncer_auth_user') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'pgbouncer_auth_user', :'pgbouncer_auth_password')
  WHERE EXISTS (SELECT FROM pg_roles WHERE rolname = :'pgbouncer_auth_user') \gexec

-- Exporter user
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'exporter_user', :'exporter_password')
  WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'exporter_user') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'exporter_user', :'exporter_password')
  WHERE EXISTS (SELECT FROM pg_roles WHERE rolname = :'exporter_user') \gexec

-- Replication user
SELECT format('CREATE ROLE %I LOGIN REPLICATION PASSWORD %L', :'replication_user', :'replication_password')
  WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'replication_user') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN REPLICATION PASSWORD %L', :'replication_user', :'replication_password')
  WHERE EXISTS (SELECT FROM pg_roles WHERE rolname = :'replication_user') \gexec

-- App database
SELECT format('CREATE DATABASE %I OWNER %I', :'app_db_name', :'app_db_user')
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'app_db_name') \gexec

-- Monitoring grants
SELECT format('GRANT pg_monitor TO %I', :'exporter_user') \gexec
SELECT format('GRANT pg_read_all_stats TO %I', :'exporter_user') \gexec
EOSQL

# ---------------------------------------------------------------------------
# Setup on app database (extensions, pgbouncer schema)
# ---------------------------------------------------------------------------
psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$APP_DB_NAME" \
  --set postgres_user="$POSTGRES_USER" \
  --set pgbouncer_auth_user="$PGBOUNCER_AUTH_USER" <<'EOSQL'
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT format('CREATE SCHEMA IF NOT EXISTS pgbouncer AUTHORIZATION %I', :'postgres_user') \gexec

CREATE OR REPLACE FUNCTION pgbouncer.user_lookup(in_username text)
RETURNS TABLE(username text, password text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT usename::text, passwd::text
  FROM pg_shadow
  WHERE usename = in_username;
$$;

REVOKE ALL ON SCHEMA pgbouncer FROM PUBLIC;
SELECT format('GRANT USAGE ON SCHEMA pgbouncer TO %I', :'pgbouncer_auth_user') \gexec
REVOKE ALL ON FUNCTION pgbouncer.user_lookup(text) FROM PUBLIC;
SELECT format('GRANT EXECUTE ON FUNCTION pgbouncer.user_lookup(text) TO %I', :'pgbouncer_auth_user') \gexec
EOSQL
