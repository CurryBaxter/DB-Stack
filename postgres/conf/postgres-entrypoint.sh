#!/bin/bash
set -euo pipefail

mkdir -p /tmp/postgres-config

envsubst < /etc/postgres/templates/postgresql.conf.template > /tmp/postgres-config/postgresql.conf
envsubst < /etc/postgres/templates/pg_hba.conf.template > /tmp/postgres-config/pg_hba.conf

# Render minimal pgbackrest.conf for archive_command
mkdir -p /etc/pgbackrest
cat > /etc/pgbackrest/pgbackrest.conf <<PGBR
[global]
repo1-path=/var/lib/pgbackrest
spool-path=/var/lib/pgbackrest/spool
log-level-console=info
log-level-file=detail

[${PGBACKREST_STANZA}]
pg1-path=${PGDATA}
pg1-port=5432
pg1-socket-path=/var/run/postgresql
PGBR

exec docker-entrypoint.sh postgres -c "config_file=/tmp/postgres-config/postgresql.conf"
