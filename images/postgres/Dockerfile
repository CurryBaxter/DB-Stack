FROM postgres:18-trixie

RUN apt-get update \
    && apt-get install -y --no-install-recommends pgbackrest gettext-base ca-certificates procps \
    && rm -rf /var/lib/apt/lists/*

COPY postgres/conf/postgres-entrypoint.sh /usr/local/bin/postgres-entrypoint.sh
RUN chmod +x /usr/local/bin/postgres-entrypoint.sh
