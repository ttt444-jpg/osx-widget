# Server-Status als macOS-Widget: Schritt-für-Schritt-Anleitung

Das Ganze besteht aus zwei Teilen:

- **Server:** eine kleine Status-API (`status_api.py`) als Container. Sie fragt Prometheus ab und liefert ein JSON unter `https://status.thomasdobler.de/status` (mit Token).
- **Mac:** eine native WidgetKit-App. Sie zeigt das JSON als Desktop-Widget in drei Größen (klein, mittel, groß).

```
server-status/
├── ANLEITUNG.md                  ← diese Datei
├── SERVER-PROMPT.md              ← Prompt für Claude auf dem Server
├── server/
│   ├── status_api.py
│   └── docker-compose.status-api.yml
└── mac/
    ├── project.yml               ← XcodeGen-Projektbeschreibung
    ├── App/ServerStatusApp.swift
    ├── Shared/ServerStatus.swift
    └── Widget/ServerStatusWidget.swift
```

---

## Teil 1: Vorbereitung (Mac, 2 Minuten)

1. Das ZIP entpacken nach `~/Documents/repos/server-status`.
2. Terminal öffnen:
   ```bash
   cd ~/Documents/repos/server-status
   ```

## Teil 2: DNS bei IONOS (5 Minuten)

Damit Let's Encrypt ein Zertifikat ausstellen kann, muss die Subdomain auf den Server zeigen.

Du brauchst nur **eine** Subdomain auf **einer** deiner Domains. Welche, ist egal. In der Anleitung steht `status.thomasdobler.de`; genauso ginge z. B. `status.the-doblers.com`. Die anderen Domains bleiben unverändert.

1. Bei IONOS einloggen → **Domains & SSL** → die gewünschte Domain (z. B. `thomasdobler.de`) anklicken → Reiter **DNS**.
2. **Datensatz hinzufügen** → Typ **A**
   - Hostname: `status`
   - Zeigt auf: `167.233.247.157`
   - TTL: Standard (1 Stunde) → **Speichern**
3. Optional dasselbe als Typ **AAAA** mit der IPv6-Adresse des Servers. Nur wenn deine anderen Domains auch einen AAAA-Eintrag auf den Server haben, sonst weglassen.
4. Den IONOS-eigenen SSL-/Weiterleitungs-Assistenten **nicht** für die Subdomain aktivieren. Das Zertifikat holt der Proxy Manager selbst.
5. Prüfen (kann ein paar Minuten dauern):
   ```bash
   dig +short status.thomasdobler.de
   ```
   Es muss die Server-IP zurückkommen.

> Andere Domain gewählt? Dann `status.thomasdobler.de` im SERVER-PROMPT und in dieser Anleitung überall ersetzen.

## Teil 3: Server (mit Claude, ca. 15–30 Minuten)

1. Server-Dateien hochladen:
   ```bash
   scp -r server diedoblers:/tmp/status-api
   ```
   Danach liegen sie auf dem Server unter `/tmp/status-api/`.
2. Auf den Server verbinden und Claude starten:
   ```bash
   ssh diedoblers
   cd /opt
   claude
   ```
3. Den kompletten Inhalt von **SERVER-PROMPT.md** einfügen und abschicken.
4. Claude arbeitet die Schritte ab und fragt bei Bedarf nach. Typische Rückfragen:
   - **Fehlende Metriken** (z. B. letzter Auto-Update-Lauf, Scrape-Job-Kennzahlen): Ergänzen lassen oder weglassen. Das Widget blendet fehlende Werte aus.
   - **Proxy Manager:** Wenn Claude nicht an die NPM-API kommt, legst du den Proxy Host im Web-UI selbst an (siehe Teil 3a).
5. Am Ende bekommst du einen Bericht mit **URL** und **Token**. Den Token sicher ablegen, z. B. in der Passwörter-App oder im Schlüsselbund.

### Teil 3a: Proxy Host manuell anlegen (nur falls nötig)

1. Proxy-Manager-Admin öffnen (wie gewohnt über den Tunnel).
2. **Hosts → Proxy Hosts → Add Proxy Host**
   - Domain Names: `status.thomasdobler.de`
   - Scheme: `http`, Forward Hostname: `monitoring-status-api`, Port: `8099`
   - **Block Common Exploits:** an
3. Reiter **SSL:** „Request a new SSL Certificate“, **Force SSL** und **HTTP/2** an, speichern.
4. Reiter **Advanced** (Custom Nginx Configuration):
   ```nginx
   location = /status {
       limit_req zone=statusapi burst=10 nodelay;
       proxy_pass http://monitoring-status-api:8099;
   }
   location / { return 404; }
   ```
   Die Zeile `limit_req_zone …` muss Claude vorher in `/data/nginx/custom/http_top.conf` angelegt haben. Sonst die `limit_req`-Zeile weglassen.

### Teil 3b: Test vom Mac aus

```bash
# ohne Token → 401
curl -s -o /dev/null -w '%{http_code}\n' https://status.thomasdobler.de/status

# mit Token → JSON
curl -s -H "Authorization: Bearer DEIN_TOKEN" https://status.thomasdobler.de/status | python3 -m json.tool | head -40
```

Wenn das JSON kommt, ist der Server fertig.

## Teil 4: Mac-App bauen (ca. 10 Minuten)

### Voraussetzungen

- macOS 14 (Sonoma) oder neuer
- **Xcode** aus dem App Store, einmal gestartet (Lizenz bestätigen, Komponenten installieren)
- **Homebrew** (falls noch nicht da: https://brew.sh)
- Eine Apple-ID in Xcode: **Xcode → Settings → Accounts → +**. Ein kostenloser Account reicht.

### Schritte

1. XcodeGen installieren und Projekt erzeugen:
   ```bash
   brew install xcodegen
   cd ~/Documents/repos/server-status/mac
   xcodegen generate
   open ServerStatus.xcodeproj
   ```
2. **Signing einstellen**, für **beide** Targets:
   - Links das Projekt „ServerStatus“ anklicken
   - Target **ServerStatus** → Reiter *Signing & Capabilities* → *Team*: deine Apple-ID wählen
   - Target **ServerStatusWidget** → dasselbe Team wählen
   - Falls ein Bundle-ID-Konflikt gemeldet wird: in `project.yml` `de.thomasdobler` durch etwas Eigenes ersetzen und `xcodegen generate` erneut ausführen.
3. Oben links als Scheme **ServerStatus** und als Ziel **My Mac** wählen, dann **⌘R** (Run).
4. Das App-Fenster öffnet sich. URL und Token eintragen und **Testen** klicken. Es sollte „✓ Alles in Ordnung …“ erscheinen.
5. **App dauerhaft installieren**, damit das Widget auch ohne Xcode bleibt:
   - **Product → Archive**, dann im Organizer **Distribute App → Custom → Copy App**
   - Die exportierte `Server-Status.app` nach **/Programme** ziehen und einmal starten.

   (Einfacher, aber weniger dauerhaft: **Product → Show Build Folder in Finder**, dann `Products/Debug/ServerStatus.app` nach /Programme kopieren.)

## Teil 5: Widget auf den Schreibtisch

1. Rechtsklick auf den Schreibtisch → **Widgets bearbeiten …**
2. In der Liste nach **Server-Status** suchen und die gewünschte Größe auf den Schreibtisch ziehen. Empfehlung: **Groß** für alles, **Klein** als Ampel.
3. Rechtsklick auf das Widget → **„Server-Status“ bearbeiten**
   - **Name:** `diedoblers`
   - **Status-URL:** `https://status.thomasdobler.de/status`
   - **Token:** den Token aus dem Bericht
4. Fertig. Das Widget aktualisiert sich etwa alle 15 Minuten. Sofort neu laden: App öffnen und auf **Widgets neu laden** klicken.

> Tipp: Unter *Systemeinstellungen → Schreibtisch & Dock → Widgets* kannst du den Stil auf **„Vollfarbig“** stellen. Sonst färbt macOS das Widget im „Monochrom“-Modus ein, wenn Fenster davor liegen.

---

## Was das Widget zeigt

| Größe | Inhalt |
|---|---|
| Klein | Ampel, Status oder erstes Problem, Websites/Dienste/Container als Zahl |
| Mittel | Zusätzlich drei Zählzeilen und CPU-/RAM-Verlauf (24 h) |
| Groß | Alles: Kacheln, Zertifikat- und Lynis-Ring, Patchstand, fail2ban, Scrape-Job, CPU/RAM-Verlauf, Platte/Swap/Load/Uptime |

Die Ampel richtet sich nach `overall` aus der API:

- **Rot:**
  - eine Website, ein Dienst oder ein Container ist down
  - ein Alarm ist aktiv
  - der Scrape-Job ist fehlgeschlagen
  - ein Zertifikat läuft in weniger als 14 Tagen ab
- **Gelb:**
  - Sicherheitsupdates offen
  - Neustart nötig
  - ein Zertifikat läuft in weniger als 30 Tagen ab
  - Platte über 85 % oder RAM über 90 %

Die Schwellen stehen in `build()` in `status_api.py`.

## Fehlerbehebung

| Problem | Lösung |
|---|---|
| Widget taucht in der Galerie nicht auf | App einmal aus /Programme starten. Notfalls abmelden und wieder anmelden, oder `killall NotificationCenter`. |
| Widget zeigt „Nicht erreichbar · Token falsch“ | Token im Widget prüfen (Rechtsklick → bearbeiten). Keine Leerzeichen am Ende. |
| „HTTP 404“ | URL muss auf `/status` enden. |
| „HTTP 502/504“ | Container läuft nicht oder Prometheus ist nicht erreichbar: auf dem Server `docker logs monitoring-status-api`. |
| Werte fehlen („–“) | Query liefert auf dem Server nichts. Claude die betreffende Query prüfen lassen. |
| Widget aktualisiert sich selten | Das ist normal, macOS legt das Budget fest. Manuell über „Widgets neu laden“ in der App. |
| Build-Fehler „No signing certificate“ | Team in **beiden** Targets setzen (Teil 4, Schritt 2). |
| Xcode meckert über `#Preview` | Xcode 15 oder neuer nötig. Notfalls den Block am Ende von `ServerStatusWidget.swift` löschen. |

## Token wechseln

1. Auf dem Server: neuen Token mit `openssl rand -hex 32` erzeugen, in `.env` ersetzen, dann `docker compose up -d status-api`.
2. Am Mac: Rechtsklick auf das Widget → bearbeiten → neuen Token eintragen.

## Später: auch aufs iPhone

Der Code ist plattformneutral (SwiftUI, WidgetKit, Charts). Für iOS in `project.yml` je ein iOS-Target ergänzen (`platform: iOS`, `deploymentTarget iOS: "17.0"`), dann laufen dieselben Widgets auf dem Home- und Sperrbildschirm.
