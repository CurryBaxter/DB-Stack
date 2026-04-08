#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Read secrets from files (if available)
# ---------------------------------------------------------------------------
read_secret() {
  local file="$1"
  if [ -f "$file" ]; then
    cat "$file" | tr -d '\n'
  fi
}

if [ -f /run/secrets/repo2_s3_key ]; then
  export BACKUP_REPO2_S3_KEY
  BACKUP_REPO2_S3_KEY=$(read_secret /run/secrets/repo2_s3_key)
fi
if [ -f /run/secrets/repo2_s3_secret ]; then
  export BACKUP_REPO2_S3_SECRET
  BACKUP_REPO2_S3_SECRET=$(read_secret /run/secrets/repo2_s3_secret)
fi

# ---------------------------------------------------------------------------
# Build optional repo2 config block
# ---------------------------------------------------------------------------
if [ "${BACKUP_REPO2_ENABLED:-false}" = "true" ]; then
  export PGBACKREST_REPO2_BLOCK
  PGBACKREST_REPO2_BLOCK=$(cat <<EOF
repo2-type=${BACKUP_REPO2_TYPE:-s3}
repo2-path=${BACKUP_REPO2_PATH:-/pgbackrest}
repo2-s3-bucket=${BACKUP_REPO2_BUCKET}
repo2-s3-endpoint=${BACKUP_REPO2_ENDPOINT}
repo2-s3-region=${BACKUP_REPO2_REGION:-eu-central-1}
repo2-s3-key=${BACKUP_REPO2_S3_KEY}
repo2-s3-key-secret=${BACKUP_REPO2_S3_SECRET}
repo2-retention-full=${BACKUP_REPO2_RETENTION_FULL:-30}
repo2-retention-diff=${BACKUP_REPO2_RETENTION_DIFF:-14}
repo2-bundle=y
repo2-block=y
EOF
)
else
  export PGBACKREST_REPO2_BLOCK="# repo2 disabled (set BACKUP_REPO2_ENABLED=true to activate)"
fi

# ---------------------------------------------------------------------------
# Render pgbackrest.conf from template
# ---------------------------------------------------------------------------
mkdir -p /var/lib/pgbackrest /var/lib/pgbackrest/spool /var/log/pgbackrest /tmp/pgbackrest-config
chmod 750 /var/lib/pgbackrest /var/lib/pgbackrest/spool
chown -R postgres:postgres /var/lib/pgbackrest /var/log/pgbackrest /tmp/pgbackrest-config

envsubst < /etc/pgbackrest/pgbackrest.conf.template > /tmp/pgbackrest-config/pgbackrest.conf

# pgbackrest reads from default location — symlink to rendered config
ln -sf /tmp/pgbackrest-config/pgbackrest.conf /etc/pgbackrest/pgbackrest.conf

# ---------------------------------------------------------------------------
# Initialize stanza as postgres user (peer auth via unix socket)
# ---------------------------------------------------------------------------
if [ -f "${PGDATA}/PG_VERSION" ]; then
  gosu postgres pgbackrest --stanza="${PGBACKREST_STANZA}" stanza-create --no-online 2>/dev/null \
    || gosu postgres pgbackrest --stanza="${PGBACKREST_STANZA}" stanza-create 2>/dev/null \
    || echo "WARN: stanza-create failed (may already exist)"

  gosu postgres pgbackrest --stanza="${PGBACKREST_STANZA}" check 2>/dev/null \
    || echo "WARN: stanza check failed (postgres may still be starting)"
fi

# ---------------------------------------------------------------------------
# Start textfile collector for Prometheus metrics
# ---------------------------------------------------------------------------
if [ -f /usr/local/bin/pgbackrest-textfile-collector.sh ]; then
  /bin/bash /usr/local/bin/pgbackrest-textfile-collector.sh &
fi

# Keep container running — backups triggered externally via systemd timer
exec tail -f /dev/null
