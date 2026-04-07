#!/bin/sh
set -eu

APP_DB_PASSWORD="$(cat "${APP_DB_PASSWORD_FILE}")"
AUTH_PASSWORD="$(cat "${PGBOUNCER_AUTH_PASSWORD_FILE}")"

envsubst < /etc/pgbouncer/pgbouncer.ini > /tmp/pgbouncer.ini
printf '"%s" "%s"\n' "${APP_DB_USER}" "${APP_DB_PASSWORD}" > /etc/pgbouncer/userlist.txt
printf '"%s" "%s"\n' "${PGBOUNCER_AUTH_USER}" "${AUTH_PASSWORD}" >> /etc/pgbouncer/userlist.txt

exec /usr/local/bin/pgbouncer /tmp/pgbouncer.ini
