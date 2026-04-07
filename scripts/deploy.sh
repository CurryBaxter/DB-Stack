#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
  ".env"
  "docker-compose.yml"
  "secrets/postgres_superuser_password.txt"
  "secrets/app_db_password.txt"
  "secrets/pgbouncer_auth_password.txt"
  "secrets/postgres_exporter_password.txt"
  "secrets/postgres_replication_password.txt"
  "secrets/grafana_admin_password.txt"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "Missing required file: $file" >&2
    exit 1
  fi
done

set_env_value() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${value}|" .env
  else
    printf '\n%s=%s\n' "$key" "$value" >> .env
  fi
}

set_env_value "APP_DB_PASSWORD" "$(tr -d '\r\n' < secrets/app_db_password.txt)"
set_env_value "PGBOUNCER_AUTH_PASSWORD" "$(tr -d '\r\n' < secrets/pgbouncer_auth_password.txt)"
set_env_value "POSTGRES_EXPORTER_PASSWORD" "$(tr -d '\r\n' < secrets/postgres_exporter_password.txt)"
set_env_value "GRAFANA_ADMIN_PASSWORD" "$(tr -d '\r\n' < secrets/grafana_admin_password.txt)"

PROJECT_NAME="$(awk -F= '/^COMPOSE_PROJECT_NAME=/{print $2}' .env | tail -n1)"
PROJECT_NAME="${PROJECT_NAME:-db-stack}"
GRAFANA_VOLUME="${PROJECT_NAME}_grafana_data"

docker compose config >/dev/null

docker compose build --pull postgres pgbackrest
docker compose pull pgbouncer postgres_exporter grafana prometheus node_exporter
docker compose up -d --remove-orphans

if docker volume inspect "$GRAFANA_VOLUME" >/dev/null 2>&1; then
  docker run --rm \
    -v "${GRAFANA_VOLUME}:/var/lib/grafana" \
    alpine sh -c 'chown -R 472:472 /var/lib/grafana && chmod -R u+rwX /var/lib/grafana' >/dev/null
  docker compose up -d grafana
fi

docker compose ps
