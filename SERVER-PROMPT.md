# Aufgabe: Status-Endpunkt für ein macOS-Widget einrichten

Du arbeitest auf meinem Ubuntu-Server bei Hetzner. Darauf laufen:

- ein Monitoring-Stack per Docker Compose, vermutlich unter /opt. Container: monitoring-prometheus-1, -grafana-1, -loki-1, -alloy-1, -blackbox-1, -alertmanager-1
- ein Nginx Proxy Manager (Container npm-app-1)
- prometheus-node-exporter als systemd-Dienst mit Textfile-Collector (monitoring-textfile.service)

Ich habe dir unter `/tmp/status-api/` zwei Dateien hochgeladen:

- `status_api.py`: eine kleine Python-API (nur Standardbibliothek). Sie fragt Prometheus ab und liefert unter `GET /status` ein JSON mit Bearer-Token aus.
- `docker-compose.status-api.yml`: ein Service-Block als Vorlage.

Ziel: Die API läuft als gehärteter Container im Monitoring-Stack und ist über den Proxy Manager unter `https://status.<DOMAIN>/status` per HTTPS erreichbar. Mein natives macOS-Widget fragt sie alle ~15 Minuten ab.

**Subdomain:** `status.thomasdobler.de` (falls das DNS noch fehlt, sag mir Bescheid; ich lege den A/AAAA-Record selbst an).

## Regeln

1. Erst erkunden, dann ändern. Vor jeder Änderung an Compose-Dateien und Configs ein Backup mit Zeitstempel anlegen.
2. SSH, ufw und fail2ban-Grundkonfiguration nicht anfassen. Nur die Container neu starten, die du änderst (status-api, bei Bedarf Prometheus nicht).
3. Keine Ports nach außen öffnen. Die API bekommt **kein** `ports:`, sie ist nur über den Proxy Manager erreichbar.
4. Den Token niemals ausgeben, loggen oder in Git-verwaltete Dateien schreiben. Nur in `.env` (Rechte 600), ganz am Ende **einmal** im Abschlussbericht für mich.
5. Wenn etwas unklar ist oder ein Schritt im Proxy-Manager-Web-UI nötig ist, mach alles andere fertig und beschreibe mir den manuellen Schritt genau.

## Schritte

### 1. Erkunden

- Compose-Projekt des Monitorings finden (`docker compose ls`, `docker inspect monitoring-prometheus-1 --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}'`).
- Docker-Netzwerke ermitteln (`docker network ls`, `docker inspect` von prometheus und npm-app-1): In welchem Netz liegt Prometheus, in welchem der Proxy Manager, und unter welchem Namen ist Prometheus im Netz erreichbar?
- Grafana-Dashboard „Server-Übersicht“ als JSON holen (Provisioning-Datei oder Grafana-API) und alle PromQL-Queries der Überblick-Panels auflisten.

### 2. Queries anpassen

In `status_api.py` gibt es das Dict `QUERIES`. Die Namen dort sind Annahmen, besonders bei Textfile-Metriken (apt, lynis, fail2ban, scrapeevents, unattended-upgrades), cAdvisor-Containern und den systemd-Diensten.

- Jede Query mit den **tatsächlichen** Metriknamen ersetzen. Am besten die Queries aus dem Dashboard übernehmen, damit Widget und Dashboard dieselben Zahlen zeigen.
- Jede Query muss genau **einen** Wert liefern (aggregieren mit `sum`/`max`/`count`).
- Jede Query vor dem Eintragen gegen die Prometheus-API testen (`curl -s 'http://<prometheus>:9090/api/v1/query' --data-urlencode 'query=…'`, notfalls per `docker exec`).
- Gibt es eine Metrik nicht (z. B. letzter Lauf von unattended-upgrades oder Scrape-Job-Kennzahlen):
  - Wenn es einfach geht, im bestehenden Textfile-Collector-Skript ergänzen, nach demselben Muster wie die vorhandenen Metriken.
  - Sonst die Query auf `vector(0)` lassen und es mir im Bericht sagen. Das Widget blendet fehlende Werte aus.
- `SERVICES` an die Liste der systemd-Dienste im Dashboard anpassen.
- Die Datei sonst nicht umbauen. Das JSON-Format muss gleich bleiben, das macOS-Widget erwartet genau diese Felder.

### 3. Integrieren

- `status_api.py` nach `<monitoring-projekt>/status-api/status_api.py` kopieren (Rechte 644).
- Token erzeugen: `openssl rand -hex 32`, als `STATUS_TOKEN=…` in die `.env` des Monitoring-Projekts (anlegen falls nötig, `chmod 600`).
- Den Service aus `docker-compose.status-api.yml` in die bestehende Compose-Datei übernehmen:
  - `PROM_URL` auf den tatsächlichen Prometheus-Hostnamen im Docker-Netz setzen.
  - Netzwerke: das Monitoring-Netz plus das Netz des Proxy Managers (als `external` eintragen, echter Name).
  - Härtung beibehalten: `read_only`, `user: 65534:65534`, `cap_drop: ALL`, `no-new-privileges`, `mem_limit`.
- `docker compose up -d status-api` und `docker logs monitoring-status-api` prüfen.

### 4. Lokal testen

Aus einem Container im selben Netz oder per `docker exec`:

- `/healthz` → `ok`
- `/status` ohne Token → 401
- `/status` mit Token → JSON

Das JSON prüfen:

- Sind `websites`, `services`, `containers`, `resources` und `history.cpu` gefüllt?
- Stimmen die Zahlen mit dem Dashboard überein?
- Steht `overall` auf `ok`, wenn alles läuft?

### 5. Proxy Manager

- Wenn möglich über die NPM-API (sonst Anleitung für mich): Proxy Host `status.thomasdobler.de` → Forward `http://monitoring-status-api:8099` (bzw. Container-Name im gemeinsamen Netz), Websockets aus, „Block Common Exploits“ an, SSL per Let's Encrypt, „Force SSL“ und HTTP/2 an.
- Unter *Advanced* nur den Pfad `/status` durchlassen und ein Rate-Limit setzen. Die `limit_req_zone` muss im http-Kontext stehen, also über eine Custom-Datei `/data/nginx/custom/http_top.conf`:
  ```
  limit_req_zone $binary_remote_addr zone=statusapi:1m rate=30r/m;
  ```
  und im Proxy Host Advanced:
  ```
  location = /status { limit_req zone=statusapi burst=10 nodelay; proxy_pass http://monitoring-status-api:8099; }
  location / { return 404; }
  ```
  Prüfen, dass die Konfiguration gültig ist (`docker exec npm-app-1 nginx -t`).

### 6. Von außen testen

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://status.thomasdobler.de/status        # 401
curl -s -H "Authorization: Bearer $STATUS_TOKEN" https://status.thomasdobler.de/status | head -c 400
```

### 7. Optional: Monitoring der API selbst

- Im Blackbox-Exporter einen Check auf `https://status.thomasdobler.de/healthz` ergänzen. Da `/healthz` am Proxy geblockt ist: Proxy-Regel für `location = /healthz` ohne Rate-Limit ergänzen, oder intern über das Docker-Netz prüfen.
- Die neue Subdomain taucht dann automatisch in der Zertifikats-Übersicht auf.

## Abschlussbericht (am Ende genau so)

1. Geänderte Dateien mit Pfad und kurzem Diff bzw. Zusammenfassung.
2. Tabelle: Query-Name → verwendete PromQL → aktueller Wert. Fehlende Metriken markieren.
3. Was ich noch manuell tun muss (DNS, NPM-UI).
4. Die fertige URL und **einmal** den Token, klar markiert, damit ich ihn ins Widget eintragen kann.
5. Wie man alles zurückrollt.
