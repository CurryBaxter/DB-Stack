#!/bin/bash
set -euo pipefail

mkdir -p /var/lib/pgbackrest /var/lib/pgbackrest/spool /var/log/pgbackrest
chmod 750 /var/lib/pgbackrest /var/lib/pgbackrest/spool

if [ -f "${PGDATA}/PG_VERSION" ]; then
  pgbackrest --stanza="${PGBACKREST_STANZA}" stanza-create || true
  pgbackrest --stanza="${PGBACKREST_STANZA}" check || true
fi

exec tail -f /dev/null
