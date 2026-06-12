#!/bin/bash
set -euo pipefail

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

IFS=',' read -r -a raw_databases <<<"${EXTRA_DB_NAMES:-}"
IFS=',' read -r -a raw_users <<<"${EXTRA_DB_USERS:-}"

databases=()
users=()
for value in "${raw_databases[@]}"; do
  value="$(trim "$value")"
  [[ -n "$value" ]] && databases+=("$value")
done
for value in "${raw_users[@]}"; do
  value="$(trim "$value")"
  [[ -n "$value" ]] && users+=("$value")
done

if [[ "${#databases[@]}" -ne "${#users[@]}" ]]; then
  echo "EXTRA_DB_NAMES and EXTRA_DB_USERS must contain the same number of entries" >&2
  exit 1
fi

for index in "${!databases[@]}"; do
  database="${databases[$index]}"
  user="${users[$index]}"
  if [[ ! "$database" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "Invalid extra database name: $database" >&2
    exit 1
  fi
  if [[ ! "$user" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
    echo "Invalid extra database user: $user" >&2
    exit 1
  fi
  secret_file="/run/secrets/extra_db_password_${user}"
  if [[ ! -s "$secret_file" ]]; then
    echo "Missing password secret: $secret_file" >&2
    exit 1
  fi
  password="$(cat "$secret_file")"

  psql -v ON_ERROR_STOP=1 \
    --username "$POSTGRES_USER" \
    --dbname postgres \
    --set db_name="$database" \
    --set db_user="$user" \
    --set db_password="$password" <<'EOSQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_password')
  WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'db_user') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'db_user', :'db_password') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'db_user')
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db_name') \gexec
EOSQL
done
