#!/bin/sh
set -eu

# ---------------------------------------------------------------------------
# Read passwords from secret files
# ---------------------------------------------------------------------------
APP_DB_PASSWORD="$(cat /run/secrets/app_db_password)"
AUTH_PASSWORD="$(cat /run/secrets/pgbouncer_auth_password)"
STATS_PASSWORD="$(cat /run/secrets/postgres_exporter_password)"

# ---------------------------------------------------------------------------
# Build the [databases] section dynamically from env vars.
# Supports the primary APP_DB_* plus any number of extra databases
# defined via EXTRA_DB_NAMES (comma-separated).
# Each extra DB reuses the same POSTGRES_HOST/POSTGRES_PORT.
# ---------------------------------------------------------------------------
DATABASES=""
# Primary database (required)
DATABASES="${DATABASES}${APP_DB_NAME} = host=${POSTGRES_HOST} port=${POSTGRES_PORT} dbname=${APP_DB_NAME}
"
# Extra databases (optional)
if [ -n "${EXTRA_DB_NAMES:-}" ]; then
  OLD_IFS="$IFS"
  IFS=","
  for db in ${EXTRA_DB_NAMES}; do
    db=$(echo "$db" | xargs)  # trim whitespace
    [ -z "$db" ] && continue
    DATABASES="${DATABASES}${db} = host=${POSTGRES_HOST} port=${POSTGRES_PORT} dbname=${db}
"
  done
  IFS="$OLD_IFS"
fi

cat > /tmp/pgbouncer.ini <<CONFIG
[databases]
${DATABASES}
[pgbouncer]
listen_addr = 0.0.0.0
listen_port = ${PGBOUNCER_LISTEN_PORT}
unix_socket_dir = /tmp

auth_type = scram-sha-256
auth_user = ${PGBOUNCER_AUTH_USER}
auth_dbname = ${APP_DB_NAME}
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

# ---------------------------------------------------------------------------
# Build the userlist.txt from secrets.
# Supports the primary APP_DB_USER plus any number of extra users
# defined via EXTRA_DB_USERS (comma-separated, each entry is "username").
# Passwords are read from secrets in /run/secrets/ matching the pattern
# "extra_db_password_<username>".
# ---------------------------------------------------------------------------
printf '"%s" "%s"\n' "${APP_DB_USER}" "${APP_DB_PASSWORD}" > /etc/pgbouncer/userlist.txt
printf '"%s" "%s"\n' "${PGBOUNCER_AUTH_USER}" "${AUTH_PASSWORD}" >> /etc/pgbouncer/userlist.txt
printf '"%s" "%s"\n' "${PGBOUNCER_STATS_USERS}" "${STATS_PASSWORD}" >> /etc/pgbouncer/userlist.txt

# Extra users (optional)
if [ -n "${EXTRA_DB_USERS:-}" ]; then
  OLD_IFS="$IFS"
  IFS=","
  for user in ${EXTRA_DB_USERS}; do
    user=$(echo "$user" | xargs)
    [ -z "$user" ] && continue
    secret_file="/run/secrets/extra_db_password_${user}"
    if [ -f "$secret_file" ]; then
      pw="$(cat "$secret_file")"
      printf '"%s" "%s"\n' "${user}" "${pw}" >> /etc/pgbouncer/userlist.txt
    else
      echo "WARNING: no password secret found for extra user '${user}' (expected ${secret_file})" >&2
    fi
  done
  IFS="$OLD_IFS"
fi

exec pgbouncer /tmp/pgbouncer.ini
