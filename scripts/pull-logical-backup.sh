#!/usr/bin/env bash
set -euo pipefail

umask 077

usage() {
  cat <<'EOF'
Usage: ./scripts/pull-logical-backup.sh [options] user@host

Stream logical PostgreSQL backups from the deployed stack to the local machine.
By default, the script exports every non-template database plus cluster globals
(roles, grants, tablespaces) from the remote `postgres` container.

Options:
  --remote-dir PATH      Remote checkout directory (default: /opt/db-stack)
  --out-dir PATH         Local backup root directory (default: ./backups)
  --db NAME              Dump only the given database. Repeatable.
  --skip-globals         Skip `pg_dumpall --globals-only`
  --ssh-port PORT        SSH port for the remote host
  --identity-file PATH   SSH identity file
  -h, --help             Show this help

Examples:
  ./scripts/pull-logical-backup.sh deploy@example.com
  ./scripts/pull-logical-backup.sh --db app --ssh-port 2222 root@db-host
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

remote=""
remote_dir="/opt/db-stack"
out_dir="./backups"
skip_globals=0
declare -a ssh_args=()
declare -a requested_dbs=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      remote_dir="$2"
      shift 2
      ;;
    --out-dir)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      out_dir="$2"
      shift 2
      ;;
    --db)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      requested_dbs+=("$2")
      shift 2
      ;;
    --skip-globals)
      skip_globals=1
      shift
      ;;
    --ssh-port)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      ssh_args+=("-p" "$2")
      shift 2
      ;;
    --identity-file)
      [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
      ssh_args+=("-i" "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$remote" ]]; then
        echo "Unexpected extra argument: $1" >&2
        usage >&2
        exit 1
      fi
      remote="$1"
      shift
      ;;
  esac
done

if [[ -z "$remote" ]]; then
  usage >&2
  exit 1
fi

fetch_database_list() {
  ssh "${ssh_args[@]}" "$remote" bash -s -- "$remote_dir" <<'REMOTE'
set -euo pipefail

remote_dir="$1"
cd "$remote_dir"

docker compose exec -T -u postgres postgres psql \
  --dbname=postgres \
  --username=postgres \
  --host=/var/run/postgresql \
  -Atqc "SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY datname"
REMOTE
}

dump_database() {
  local db_name="$1"
  local output_path="$2"

  if ! ssh "${ssh_args[@]}" "$remote" bash -s -- "$remote_dir" "$db_name" <<'REMOTE' > "$output_path"; then
set -euo pipefail

remote_dir="$1"
db_name="$2"
cd "$remote_dir"

exec docker compose exec -T -u postgres postgres pg_dump \
  --format=custom \
  --compress=9 \
  --create \
  --dbname="$db_name" \
  --username=postgres \
  --host=/var/run/postgresql
REMOTE
    rm -f "$output_path"
    return 1
  fi
}

dump_globals() {
  local output_path="$1"

  if ! ssh "${ssh_args[@]}" "$remote" bash -s -- "$remote_dir" <<'REMOTE' > "$output_path"; then
set -euo pipefail

remote_dir="$1"
cd "$remote_dir"

exec docker compose exec -T -u postgres postgres pg_dumpall \
  --globals-only \
  --username=postgres \
  --host=/var/run/postgresql
REMOTE
    rm -f "$output_path"
    return 1
  fi
}

write_checksums() {
  local target_dir="$1"

  if command -v shasum >/dev/null 2>&1; then
    (
      cd "$target_dir"
      shasum -a 256 ./* > SHA256SUMS
    )
  elif command -v sha256sum >/dev/null 2>&1; then
    (
      cd "$target_dir"
      sha256sum ./* > SHA256SUMS
    )
  fi
}

safe_remote="$(printf '%s' "$remote" | tr -c 'A-Za-z0-9._-' '_')"
timestamp_utc="$(date -u '+%Y%m%dT%H%M%SZ')"
backup_dir="${out_dir%/}/${safe_remote}_${timestamp_utc}"

mkdir -p "$backup_dir"

declare -a dbs=()
if [[ ${#requested_dbs[@]} -gt 0 ]]; then
  dbs=("${requested_dbs[@]}")
else
  while IFS= read -r db_name; do
    [[ -n "$db_name" ]] || continue
    dbs+=("$db_name")
  done < <(fetch_database_list)
fi

if [[ ${#dbs[@]} -eq 0 ]]; then
  echo "No databases found to dump." >&2
  exit 1
fi

manifest_path="$backup_dir/manifest.txt"
{
  printf 'created_at_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'remote=%s\n' "$remote"
  printf 'remote_dir=%s\n' "$remote_dir"
  printf 'globals_dump=%s\n' "$([[ $skip_globals -eq 1 ]] && echo "false" || echo "true")"
} > "$manifest_path"

for db_name in "${dbs[@]}"; do
  safe_db_name="$(printf '%s' "$db_name" | tr -c 'A-Za-z0-9._-' '_')"
  dump_path="$backup_dir/${safe_db_name}.dump"
  log "Dumping database $db_name to $dump_path"
  dump_database "$db_name" "$dump_path"
  printf 'database=%s\n' "$db_name" >> "$manifest_path"
done

if [[ $skip_globals -eq 0 ]]; then
  globals_path="$backup_dir/globals.sql"
  log "Dumping cluster globals to $globals_path"
  dump_globals "$globals_path"
fi

write_checksums "$backup_dir"

log "Backup written to $backup_dir"
printf '%s\n' "$backup_dir"
