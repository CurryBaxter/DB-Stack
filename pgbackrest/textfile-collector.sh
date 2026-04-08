#!/bin/bash
# Collects pgBackRest metrics and writes them in Prometheus textfile format.
# Runs as a loop inside the pgbackrest sidecar; node_exporter picks up the output
# via --collector.textfile.directory.

set -euo pipefail

TEXTFILE_DIR="/var/lib/node-exporter/textfile"
INTERVAL="${METRICS_COLLECTOR_INTERVAL:-60}"
STANZA="${PGBACKREST_STANZA:-main}"

mkdir -p "${TEXTFILE_DIR}"

while true; do
  TMP="${TEXTFILE_DIR}/pgbackrest.prom.tmp"
  OUT="${TEXTFILE_DIR}/pgbackrest.prom"

  {
    # Attempt to get pgbackrest info as JSON
    if INFO=$(pgbackrest --stanza="${STANZA}" --output=json info 2>/dev/null); then

      echo "# HELP pgbackrest_info pgBackRest stanza information"
      echo "# TYPE pgbackrest_info gauge"
      echo "pgbackrest_info{stanza=\"${STANZA}\"} 1"

      echo "# HELP pgbackrest_backup_last_epoch Epoch time of last completed backup by type"
      echo "# TYPE pgbackrest_backup_last_epoch gauge"

      echo "# HELP pgbackrest_backup_last_size_bytes Size of last backup in bytes by type"
      echo "# TYPE pgbackrest_backup_last_size_bytes gauge"

      echo "# HELP pgbackrest_backup_last_duration_seconds Duration of last backup in seconds by type"
      echo "# TYPE pgbackrest_backup_last_duration_seconds gauge"

      echo "# HELP pgbackrest_backup_count Number of backups by type"
      echo "# TYPE pgbackrest_backup_count gauge"

      echo "# HELP pgbackrest_backup_since_last_seconds Seconds since last completed backup (any type)"
      echo "# TYPE pgbackrest_backup_since_last_seconds gauge"

      echo "# HELP pgbackrest_repo_status Repository status (1=ok, 0=error)"
      echo "# TYPE pgbackrest_repo_status gauge"

      # Parse JSON with basic tools (no jq dependency assumed — use python3 if available, else jq)
      if command -v python3 >/dev/null 2>&1; then
        python3 - "${INFO}" "${STANZA}" <<'PYEOF'
import json, sys, time

data = json.loads(sys.argv[1])
stanza_name = sys.argv[2]

for stanza in data:
    if stanza.get("name") != stanza_name:
        continue

    repo_status = 0 if stanza.get("status", {}).get("code", 1) == 0 else 0
    # code 0 = ok
    repo_status = 1 if stanza.get("status", {}).get("code") == 0 else 0
    print(f'pgbackrest_repo_status{{stanza="{stanza_name}"}} {repo_status}')

    backups = stanza.get("backup", [])
    by_type = {}
    latest_epoch = 0

    for b in backups:
        btype = b.get("type", "unknown")
        ts_stop = b.get("timestamp", {}).get("stop", 0)
        ts_start = b.get("timestamp", {}).get("start", 0)
        size = b.get("info", {}).get("size", 0)
        duration = ts_stop - ts_start if ts_stop and ts_start else 0

        if btype not in by_type or ts_stop > by_type[btype]["epoch"]:
            by_type[btype] = {"epoch": ts_stop, "size": size, "duration": duration}

        if ts_stop > latest_epoch:
            latest_epoch = ts_stop

        by_type.setdefault(f"_count_{btype}", {"count": 0})
        by_type[f"_count_{btype}"]["count"] = by_type.get(f"_count_{btype}", {}).get("count", 0) + 1

    for btype, vals in by_type.items():
        if btype.startswith("_count_"):
            real_type = btype.replace("_count_", "")
            print(f'pgbackrest_backup_count{{stanza="{stanza_name}",type="{real_type}"}} {vals["count"]}')
        else:
            print(f'pgbackrest_backup_last_epoch{{stanza="{stanza_name}",type="{btype}"}} {vals["epoch"]}')
            print(f'pgbackrest_backup_last_size_bytes{{stanza="{stanza_name}",type="{btype}"}} {vals["size"]}')
            print(f'pgbackrest_backup_last_duration_seconds{{stanza="{stanza_name}",type="{btype}"}} {vals["duration"]}')

    if latest_epoch > 0:
        since = int(time.time()) - latest_epoch
        print(f'pgbackrest_backup_since_last_seconds{{stanza="{stanza_name}"}} {since}')
    else:
        print(f'pgbackrest_backup_since_last_seconds{{stanza="{stanza_name}"}} -1')
PYEOF
      else
        echo "pgbackrest_repo_status{stanza=\"${STANZA}\"} 0"
        echo "# python3 not available, metrics limited"
      fi

    else
      echo "# HELP pgbackrest_up Whether pgbackrest info succeeded"
      echo "# TYPE pgbackrest_up gauge"
      echo "pgbackrest_up{stanza=\"${STANZA}\"} 0"
    fi
  } > "${TMP}"

  mv "${TMP}" "${OUT}"
  sleep "${INTERVAL}"
done
