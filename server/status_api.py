#!/usr/bin/env python3
"""
Status-API für das macOS-Widget.

Fragt Prometheus ab, verdichtet alles zu einem kleinen JSON und liefert es
unter GET /status aus (Bearer-Token). GET /healthz ohne Auth für Docker.

Nur Standardbibliothek, läuft z. B. im Image python:3.12-alpine.

Umgebungsvariablen:
  STATUS_TOKEN   Pflicht, mindestens 32 Zeichen (openssl rand -hex 32)
  PROM_URL       Default http://prometheus:9090
  PORT           Default 8099
  CACHE_SECONDS  Default 60
"""
import hmac
import json
import math
import os
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROM = os.environ.get("PROM_URL", "http://prometheus:9090").rstrip("/")
TOKEN = os.environ.get("STATUS_TOKEN", "")
PORT = int(os.environ.get("PORT", "8099"))
CACHE_SECONDS = int(os.environ.get("CACHE_SECONDS", "60"))

if len(TOKEN) < 32:
    sys.exit("STATUS_TOKEN fehlt oder ist kürzer als 32 Zeichen")

# ---------------------------------------------------------------------------
# ANPASSEN: Die Queries müssen zu den Metriken auf dem Server passen.
# Am einfachsten aus dem Grafana-Dashboard "Server-Übersicht" übernehmen.
# Jede Query muss genau EINEN Wert liefern. Liefert sie nichts, steht im
# JSON null und das Widget blendet den Wert aus.
# ---------------------------------------------------------------------------
SERVICES = (
    "auditd|chrony|containerd|cron|docker|fail2ban|prometheus-node-exporter|"
    "scrapeeventsffm|ssh|unattended-upgrades|weddingpage"
)

QUERIES = {
    # Verfügbarkeit
    "websites_up": 'sum(probe_success{job="websites"})',
    "websites_total": 'count(probe_success{job="websites"})',
    "internal_up": 'sum(probe_success{job="internal"})',
    "internal_total": 'count(probe_success{job="internal"})',
    "services_up": f'sum(node_systemd_unit_state{{state="active", name=~"({SERVICES})\\\\.service"}})',
    "services_total": f'count(node_systemd_unit_state{{state="active", name=~"({SERVICES})\\\\.service"}})',
    "containers_up": 'count((time() - container_last_seen{name!=""}) < 120)',
    "containers_total": 'count(container_last_seen{name!=""} > time() - 86400)',
    "alerts": 'count(ALERTS{alertstate="firing"}) or vector(0)',
    # Patchstand (Textfile-Collector, Namen prüfen!)
    "updates": "sum(apt_upgrades_pending) or vector(0)",
    "security": 'sum(apt_upgrades_pending{origin=~"(?i).*security.*"}) or vector(0)',
    "reboot": "max(node_reboot_required)",
    "last_auto_update_hours": "(time() - max(unattended_upgrades_last_run_timestamp_seconds)) / 3600",
    # Sicherheit (Textfile-Collector, Namen prüfen!)
    "cert_min_days": "min((probe_ssl_earliest_cert_expiry - time()) / 86400)",
    "lynis": "max(lynis_hardening_index)",
    "fail2ban": "sum(fail2ban_banned_ips)",
    # Scrape-Job (Namen prüfen!)
    "scrape_ok": "max(scrapeevents_last_run_success)",
    "scrape_sources_ok": "max(scrapeevents_sources_ok)",
    "scrape_sources_total": "max(scrapeevents_sources_total)",
    "scrape_last_run_hours": "(time() - max(scrapeevents_last_run_timestamp_seconds)) / 3600",
    # Ressourcen
    "cpu": '100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))',
    "ram": "100 * (1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))",
    "swap": "100 * (1 - sum(node_memory_SwapFree_bytes) / sum(node_memory_SwapTotal_bytes))",
    "disk": '100 * (1 - max(node_filesystem_avail_bytes{mountpoint="/"}) / max(node_filesystem_size_bytes{mountpoint="/"}))',
    "load5": "max(node_load5)",
    "uptime_days": "(time() - max(node_boot_time_seconds)) / 86400",
}

HISTORY = {
    "cpu": QUERIES["cpu"],
    "ram": QUERIES["ram"],
}


def _get(path, params):
    url = f"{PROM}{path}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(url, timeout=10) as r:
        body = json.load(r)
    if body.get("status") != "success":
        raise RuntimeError(body.get("error", "Prometheus-Fehler"))
    return body["data"]["result"]


def _num(v):
    try:
        f = float(v)
    except (TypeError, ValueError):
        return None
    return None if math.isnan(f) or math.isinf(f) else f


def q(expr):
    try:
        res = _get("/api/v1/query", {"query": expr})
    except Exception as e:  # noqa: BLE001
        print(f"Query fehlgeschlagen: {expr}: {e}", file=sys.stderr)
        return None
    if not res:
        return None
    return _num(res[0]["value"][1])


def qr(expr, hours=24, step=1800):
    end = time.time()
    try:
        res = _get("/api/v1/query_range", {
            "query": expr, "start": end - hours * 3600, "end": end, "step": step,
        })
    except Exception as e:  # noqa: BLE001
        print(f"Range-Query fehlgeschlagen: {expr}: {e}", file=sys.stderr)
        return []
    if not res:
        return []
    return [round(_num(v) or 0.0, 1) for _, v in res[0]["values"]]


def _int(v):
    return None if v is None else int(round(v))


def _rnd(v, n=1):
    return None if v is None else round(v, n)


def _count(up, total):
    if total is None:
        return None
    return {"up": _int(up or 0), "total": _int(total)}


def build():
    v = {k: q(e) for k, e in QUERIES.items()}

    websites = _count(v["websites_up"], v["websites_total"])
    internal = _count(v["internal_up"], v["internal_total"])
    services = _count(v["services_up"], v["services_total"])
    if services and internal:  # interne Dienste zu den Diensten zählen
        services = {"up": services["up"] + internal["up"],
                    "total": services["total"] + internal["total"]}
    services = services or internal
    containers = _count(v["containers_up"], v["containers_total"])

    crit, warn = [], []

    def down(name, c):
        if c and c["up"] < c["total"]:
            crit.append(f"{c['total'] - c['up']} {name} gestört")

    down("Websites", websites)
    down("Dienste", services)
    down("Container", containers)

    alerts = _int(v["alerts"])
    if alerts:
        crit.append(f"{alerts} Alarm(e) aktiv")

    scrape_ok = v["scrape_ok"]
    if scrape_ok is not None and scrape_ok < 1:
        crit.append("Scrape-Job fehlgeschlagen")

    cert = _int(v["cert_min_days"])
    if cert is not None:
        if cert < 14:
            crit.append(f"Zertifikat läuft in {cert} Tagen ab")
        elif cert < 30:
            warn.append(f"Zertifikat läuft in {cert} Tagen ab")

    security = _int(v["security"])
    if security:
        warn.append(f"{security} Sicherheitsupdate(s)")
    reboot = None if v["reboot"] is None else v["reboot"] >= 1
    if reboot:
        warn.append("Neustart nötig")
    if (v["disk"] or 0) > 85:
        warn.append(f"Platte {v['disk']:.0f} % voll")
    if (v["ram"] or 0) > 90:
        warn.append(f"RAM {v['ram']:.0f} %")

    overall = "crit" if crit else "warn" if warn else "ok"

    return {
        "generatedAt": time.time(),
        "overall": overall,
        "problems": crit + warn,
        "websites": websites,
        "services": services,
        "containers": containers,
        "alerts": alerts,
        "patches": {
            "updates": _int(v["updates"]),
            "security": security,
            "rebootRequired": reboot,
            "lastAutoUpdateHours": _rnd(v["last_auto_update_hours"]),
        },
        "certMinDays": cert,
        "lynis": _int(v["lynis"]),
        "fail2banBanned": _int(v["fail2ban"]),
        "scrape": {
            "ok": None if scrape_ok is None else scrape_ok >= 1,
            "sourcesOk": _int(v["scrape_sources_ok"]),
            "sourcesTotal": _int(v["scrape_sources_total"]),
            "lastRunHours": _rnd(v["scrape_last_run_hours"]),
        },
        "resources": {
            "cpu": _rnd(v["cpu"]),
            "ram": _rnd(v["ram"]),
            "swap": _rnd(v["swap"]),
            "disk": _rnd(v["disk"]),
            "load5": _rnd(v["load5"], 2),
            "uptimeDays": _rnd(v["uptime_days"]),
        },
        "history": {k: qr(e) for k, e in HISTORY.items()},
    }


_cache = {"at": 0.0, "body": b""}
_lock = threading.Lock()


def cached():
    with _lock:
        if time.time() - _cache["at"] > CACHE_SECONDS or not _cache["body"]:
            _cache["body"] = json.dumps(build(), ensure_ascii=False).encode()
            _cache["at"] = time.time()
        return _cache["body"]


class Handler(BaseHTTPRequestHandler):
    server_version = "status-api"
    sys_version = ""

    def _send(self, code, body=b"", ctype="application/json; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path == "/healthz":
            return self._send(200, b"ok", "text/plain")
        if path != "/status":
            return self._send(404, b'{"error":"not found"}')
        auth = self.headers.get("Authorization", "")
        given = auth[7:] if auth.startswith("Bearer ") else ""
        if not hmac.compare_digest(given.encode(), TOKEN.encode()):
            return self._send(401, b'{"error":"unauthorized"}')
        try:
            self._send(200, cached())
        except Exception as e:  # noqa: BLE001
            print(f"Fehler: {e}", file=sys.stderr)
            self._send(502, b'{"error":"prometheus nicht erreichbar"}')

    def log_message(self, fmt, *args):
        pass  # keine Access-Logs, die macht der Proxy


if __name__ == "__main__":
    print(f"status-api auf :{PORT}, Prometheus {PROM}", file=sys.stderr)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
