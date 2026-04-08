#!/bin/sh
set -eu

# ---------------------------------------------------------------------------
# Read passwords from secret files
# ---------------------------------------------------------------------------
APP_DB_PASSWORD="$(cat /run/secrets/app_db_password)"
AUTH_PASSWORD="$(cat /run/secrets/pgbouncer_auth_password)"
STATS_PASSWORD="$(cat /run/secrets/postgres_exporter_password)"

cat > /tmp/pgbouncer.ini <<CONFIG
[databases]
${APP_DB_NAME} = host=${POSTGRES_HOST} port=${POSTGRES_PORT} dbname=${APP_DB_NAME}

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = ${PGBOUNCER_LISTEN_PORT}
unix_socket_dir = /tmp

auth_type = scram-sha-256
auth_user = ${PGBOUNCER_AUTH_USER}
auth_query = SELECT username, password FROM pgbouncer.user_lookup(\$1)
auth_file = /etc/pgbouncer/userlist.txt

pool_mode = ${PGBOUNCER_POOL_MODE}
max_client_conn = ${PGBOUNCER_MAX_CLIENT_CONN}
default_pool_size = ${PGBOUNCER_DEFAULT_POOL_SIZE}
reserve_pool_size = ${PGBOUNCER_RESERVE_POOL_SIZE}
reserve_pool_timeout = ${PGBOUNCER_RESERVE_POOL_TIMEOUT}
server_reset_query = ${PGBOUNCER_SERVER_RESET_QUERY}
ignore_startup_parameters = extra_float_digits,options

admin_users = ${PGBOUNCER_ADMIN_USERS}
stats_users = ${PGBOUNCER_STATS_USERS}

server_tls_sslmode = disable
client_tls_sslmode = disable

log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
CONFIG

printf '"%s" "%s"\n' "${APP_DB_USER}" "${APP_DB_PASSWORD}" > /etc/pgbouncer/userlist.txt
printf '"%s" "%s"\n' "${PGBOUNCER_AUTH_USER}" "${AUTH_PASSWORD}" >> /etc/pgbouncer/userlist.txt
printf '"%s" "%s"\n' "${PGBOUNCER_STATS_USERS}" "${STATS_PASSWORD}" >> /etc/pgbouncer/userlist.txt

exec pgbouncer /tmp/pgbouncer.ini
