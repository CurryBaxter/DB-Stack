# DB-Stack

Produktionsnahe Docker-Compose-Basis für einen self-managed PostgreSQL-Server auf einem einzelnen Hetzner-Host mit:

- PostgreSQL 18 als Primary
- PgBouncer für Connection Pooling
- pgBackRest für Base Backups, WAL-Archivierung und PITR
- postgres_exporter für PostgreSQL-Metriken
- node_exporter für Host-Metriken
- Prometheus für Scraping und Storage
- Grafana für Dashboards

## Struktur

```text
.
├── docker-compose.yml
├── .env.example
├── images/
│   └── postgres/
│       └── Dockerfile
├── postgres/
│   ├── conf/
│   │   ├── pg_hba.conf.template
│   │   ├── postgres-entrypoint.sh
│   │   └── postgresql.conf.template
│   └── initdb/
│       └── 01-bootstrap.sh
├── pgbouncer/
│   ├── entrypoint.sh
│   └── pgbouncer.ini
├── pgbackrest/
│   ├── entrypoint.sh
│   └── pgbackrest.conf
├── prometheus/
│   └── prometheus.yml
└── grafana/
    ├── dashboards/
    └── provisioning/
        ├── dashboards/
        │   └── dashboards.yml
        └── datasources/
            └── prometheus.yml
```

## Container-Rollen

- `postgres`: Primary-Datenbank, persistente Datenhaltung, WAL-Erzeugung und `archive-push` via pgBackRest.
- `pgbouncer`: Fängt Verbindungs-Spitzen der WebApp ab und reduziert Backend-Connections.
- `pgbackrest`: Verwaltet das Backup-Repository, führt `stanza-create`, `check`, Backups und später Restores aus.
- `postgres_exporter`: Liefert PostgreSQL-Metriken an Prometheus.
- `node_exporter`: Liefert Host-Metriken wie CPU, RAM, Filesystem und Prozesse.
- `prometheus`: Scraped Exporter und speichert Zeitreihen.
- `grafana`: Visualisiert Dashboards und Alerts.

## Inbetriebnahme

1. `.env.example` nach `.env` kopieren und Werte anpassen.
2. `.env` mit den Laufzeit-Passwörtern für `PgBouncer`, `postgres_exporter` und `Grafana` ergänzen.
3. `secrets/` anlegen und die PostgreSQL-seitigen Passwortdateien mit `chmod 600` ablegen.
4. Stack starten: `docker compose up -d --build`
5. Nach dem ersten erfolgreichen Start `pgbackrest` prüfen:
   - `docker compose exec pgbackrest pgbackrest --stanza=main info`
   - `docker compose exec pgbackrest pgbackrest --stanza=main check`
6. Erstes Full Backup ausführen:
   - `docker compose exec -T pgbackrest pgbackrest --stanza=main backup --type=full`

Für wiederholbare Deployments gilt in dieser Basis:

- PostgreSQL-Primary und Replikation nutzen Docker-Secrets.
- `PgBouncer`, `postgres_exporter` und `Grafana` nutzen `.env`, weil die verwendeten Images im Compose-Betrieb Secret-Dateien nicht zuverlässig konsumieren.

## Backup-Strategie

Docker-Volumes ersetzen keine PostgreSQL-konforme Backup-Strategie. Dieser Stack sichert logisch korrekt über pgBackRest:

- Base Backups via `pgbackrest backup`
- kontinuierliche WAL-Archivierung über `archive_command`
- Point-in-Time-Recovery über Backup-Repository plus WAL

Pragmatischer Betriebsansatz auf einem einzelnen Host unter Debian 13:

- tägliches Full- oder Differential-Backup per `systemd timer` auf dem Host
- engmaschige `check`-Runs, z. B. alle 15 Minuten
- zusätzliche externe Replikation des Backup-Repositories, etwa per `restic`, `rclone` oder Storage Box

## Regelmäßig zu sichernde Verzeichnisse

- Docker-Volume `postgres_data`
  - Nicht als primäre Backup-Quelle für Restores, aber relevant für schnellen lokalen Rollback und forensische Analyse.
- Docker-Volume `pgbackrest_repo`
  - Kritisch: enthält Base Backups und archivierte WAL-Segmente.
- Docker-Volume `prometheus_data`
  - Optional für Metrik-Historie.
- Docker-Volume `grafana_data`
  - Optional für Dashboards, Nutzer und Alerting-States.
- Projektverzeichnis mit `docker-compose.yml`, `.env` und Konfigurationen
  - Nötig für reproduzierbare Restores.

## Restore und Testen

Backups müssen regelmäßig getestet werden. Minimaler Ablauf:

1. Separaten Restore-Pfad oder separaten Test-Host bereitstellen.
2. `postgres` auf dem Ziel gestoppt lassen und leeres Datenverzeichnis verwenden.
3. Restore ausführen, z. B.:
   - `docker compose run --rm pgbackrest pgbackrest --stanza=main --delta restore`
4. Für PITR zusätzlich `--type=time --target="2026-04-07 12:00:00+00"` verwenden.
5. PostgreSQL mit der restaurierten Datenbasis starten und Integrität der Anwendung testen.

## Security-Hardening für Hetzner / Debian 13

- Nur `PgBouncer` und `Grafana` an `127.0.0.1` binden und extern nur über Reverse Proxy oder VPN freigeben.
- Host-Firewall aktivieren, etwa mit `nftables` oder `ufw`.
- SSH nur mit Schlüsseln, Root-Login deaktivieren, `fail2ban` oder ähnlich nutzen.
- Docker und Debian zeitnah patchen, Reboot-Fenster planen.
- Docker-Volume- und Secret-Dateien strikt auf Root beschränken.
- Für Internet-Traffic TLS am Reverse Proxy terminieren; innerhalb des Hosts nur interne Netze verwenden.
- Disk- und IO-Limits beobachten; auf Hetzner möglichst lokale NVMe-Ressourcen passend dimensionieren.
- Swap bewusst konfigurieren und OOM-Risiko minimieren.

## Erweiterbarkeit Richtung Replicas

Die Konfiguration ist auf spätere Read Replicas vorbereitet:

- `wal_level = replica`
- `max_wal_senders` und `max_replication_slots` gesetzt
- Replikationsrolle wird beim Bootstrap erzeugt
- WAL-Archivierung läuft bereits über pgBackRest

Für spätere Replicas kommen typischerweise dazu:

- eigener Replica-Compose-Stack oder zweiter Host
- `pg_basebackup` oder pgBackRest-Restore für Initial-Sync
- Streaming Replication über die Rolle `${POSTGRES_REPLICATION_USER:-replicator}`
