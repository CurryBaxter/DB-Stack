from pathlib import Path


p = Path("docker-compose.yml")
s = p.read_text()

s = s.replace(
'''  postgres_exporter:
    image: quay.io/prometheuscommunity/postgres-exporter:v0.15.0
    container_name: ${COMPOSE_PROJECT_NAME:-db-stack}-postgres-exporter
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      DATA_SOURCE_URI: "postgres:${POSTGRES_PORT_INTERNAL:-5432}/${POSTGRES_DEFAULT_DB:-postgres}?sslmode=disable"
      DATA_SOURCE_USER: ${POSTGRES_EXPORTER_USER:-postgres_exporter}
      PG_EXPORTER_AUTO_DISCOVER_DATABASES: "false"
      PG_EXPORTER_DISABLE_DEFAULT_METRICS: "false"
      PG_EXPORTER_DISABLE_SETTINGS_METRICS: "false"
    secrets:
      - postgres_exporter_password
    command:
      - /bin/sh
      - -ec
      - |
        export DATA_SOURCE_PASS="$$(cat /run/secrets/postgres_exporter_password)"
        exec postgres_exporter
    expose:
      - "9187"
    networks:
      - db_plane
      - obs_plane
''',
'''  postgres_exporter:
    image: quay.io/prometheuscommunity/postgres-exporter:v0.15.0
    container_name: ${COMPOSE_PROJECT_NAME:-db-stack}-postgres-exporter
    user: "0:0"
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      DATA_SOURCE_URI: "postgres:${POSTGRES_PORT_INTERNAL:-5432}/${POSTGRES_DEFAULT_DB:-postgres}?sslmode=disable"
      DATA_SOURCE_USER: ${POSTGRES_EXPORTER_USER:-postgres_exporter}
      PG_EXPORTER_AUTO_DISCOVER_DATABASES: "false"
      PG_EXPORTER_DISABLE_DEFAULT_METRICS: "false"
      PG_EXPORTER_DISABLE_SETTINGS_METRICS: "false"
    secrets:
      - postgres_exporter_password
    entrypoint:
      - /bin/sh
      - -ec
      - |
        export DATA_SOURCE_PASS="$$(cat /run/secrets/postgres_exporter_password)"
        exec /bin/postgres_exporter
    expose:
      - "9187"
    networks:
      - db_plane
      - obs_plane
''')

s = s.replace(
'''  pgbouncer:
    image: edoburu/pgbouncer:v1.25.1-p0
    container_name: ${COMPOSE_PROJECT_NAME:-db-stack}-pgbouncer
''',
'''  pgbouncer:
    image: edoburu/pgbouncer:v1.25.1-p0
    container_name: ${COMPOSE_PROJECT_NAME:-db-stack}-pgbouncer
    user: "0:0"
''')

s = s.replace(
'''  grafana:
    image: grafana/grafana-oss:11.1.3
    container_name: ${COMPOSE_PROJECT_NAME:-db-stack}-grafana
''',
'''  grafana:
    image: grafana/grafana-oss:11.1.3
    container_name: ${COMPOSE_PROJECT_NAME:-db-stack}-grafana
    user: "0:0"
''')

p.write_text(s)
