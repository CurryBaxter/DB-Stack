#!/bin/sh
set -eu

docker compose exec postgres /usr/local/bin/provision-extra-dbs.sh
docker compose restart pgbouncer
