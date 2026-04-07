#!/bin/bash
set -euo pipefail

mkdir -p /tmp/postgres-config
envsubst < /etc/postgres/templates/postgresql.conf.template > /tmp/postgres-config/postgresql.conf
envsubst < /etc/postgres/templates/pg_hba.conf.template > /tmp/postgres-config/pg_hba.conf

exec docker-entrypoint.sh postgres -c "config_file=/tmp/postgres-config/postgresql.conf"
