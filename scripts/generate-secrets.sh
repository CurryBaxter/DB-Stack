#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Generate initial secret files for the DB stack.
# Safe to re-run: existing secrets are never overwritten.
# ---------------------------------------------------------------------------

SECRETS_DIR="${1:-./secrets}"

mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

generate() {
  local file="${SECRETS_DIR}/$1"
  local length="${2:-32}"

  if [ -f "$file" ]; then
    echo "  SKIP  $file (already exists)"
    return
  fi

  openssl rand -base64 "$length" | tr -d '\n' > "$file"
  chmod 644 "$file"
  echo "  NEW   $file"
}

echo "Generating secrets in ${SECRETS_DIR}/ ..."
echo ""

generate "postgres_superuser_password.txt" 32
generate "app_db_password.txt" 32
generate "pgbouncer_auth_password.txt" 32
generate "postgres_exporter_password.txt" 32
generate "postgres_replication_password.txt" 32
generate "grafana_admin_password.txt" 32

# S3 repo2 secrets — create empty placeholders so docker compose doesn't fail
for f in repo2_s3_key.txt repo2_s3_secret.txt; do
  file="${SECRETS_DIR}/$f"
  if [ ! -f "$file" ]; then
    touch "$file"
    chmod 644 "$file"
    echo "  NEW   $file (empty placeholder — fill in when enabling repo2)"
  else
    echo "  SKIP  $file (already exists)"
  fi
done

echo ""
echo "Done. Secret files are in ${SECRETS_DIR}/"
echo "Remember: never commit this directory to git."
