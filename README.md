# osx-widget

Eine Sammlung nativer macOS-Desktop-Widgets (SwiftUI + WidgetKit) und **eine Config-App „OSX Widgets“**, mit der du alle Widgets einstellst.

| Widget | Zeigt | Einstellungen |
|---|---|---|
| **Stock** | ETF- und Aktienkurse wie bei Trade Republic (Kurse von Lang & Schwarz), Gewinn/Verlust seit Kauf | Watchlist und Kaufkurse in der Config-App · Filter, Zeitraum und Sortierung am Widget |

## Aufbau

```
osx-widget/
├── project.yml                 ← ein Xcode-Projekt (XcodeGen) für alles
├── ConfigApp/                  ← die Config-App „OSX Widgets“
│   ├── ConfigApp.swift         ← Fenster mit Seitenleiste + Widget-Verzeichnis (WidgetModule.all)
│   └── Stock/StockSettingsView.swift
├── Widgets/                    ← eine Widget-Extension mit allen Widgets
│   ├── WidgetsBundle.swift     ← Liste aller Widgets
│   └── Stock/StockWidget.swift
└── Shared/                     ← wird in App und Extension kompiliert
    ├── Core/                   ← gemeinsamer Speicher (App Group), Farben
    └── Stock/StockData.swift   ← Datenmodell, Kursabruf, Formatierung
```

App und Extension teilen ihre Einstellungen über die App Group `<TeamID>.de.thomasdobler.osxwidgets.shared` (`SharedStore` in `Shared/Core`). Die Config-App schreibt, die Widgets lesen.

## Bauen

Voraussetzung: **Xcode** (einmal starten bzw. `sudo xcodebuild -license accept`), Apple-ID unter *Xcode → Settings → Accounts* (kostenloser Account reicht), und XcodeGen.

```bash
brew install xcodegen
cd ~/Documents/repos/osx-widget
xcodegen generate
open OSXWidgets.xcodeproj
```

1. Für **beide** Targets (`OSXWidgets` und `OSXWidgetsExtension`) unter *Signing & Capabilities* dein **Team** wählen.
2. Scheme **OSXWidgets**, Ziel **My Mac**, dann **⌘R**.
3. Dauerhaft installieren: *Product → Archive → Distribute App → Custom → Copy App*, dann `OSX Widgets.app` nach **/Programme** ziehen und einmal starten.

Widgets hinzufügen: Rechtsklick auf den Schreibtisch → *Widgets bearbeiten* → **OSX Widgets**.

## Neues Widget hinzufügen

Beispiel „Wetter“:

1. **Daten:** `Shared/Weather/WeatherData.swift` mit Modell, Abruf und einem Store:
   ```swift
   enum WeatherStore {
       static let kind = "WeatherWidget"
       static func load() -> WeatherSettings { SharedStore.load(WeatherSettings.self, key: "weather.settings") ?? .default }
       static func save(_ s: WeatherSettings) { SharedStore.save(s, key: "weather.settings", reloading: kind) }
   }
   ```
2. **Widget:** `Widgets/Weather/WeatherWidget.swift` mit `kind: WeatherStore.kind`, dann in `Widgets/WidgetsBundle.swift` eintragen.
3. **Einstellungen:** `ConfigApp/Weather/WeatherSettingsView.swift`, dann in `ConfigApp/ConfigApp.swift` bei `WidgetModule.all` und im `switch` von `settings` ergänzen.
4. `xcodegen generate`, fertig. Neue Ordner werden automatisch erkannt.

Konventionen:
- Typnamen mit Widget-Präfix (`WeatherRow`, `WeatherProvider`), weil alle Widgets in einem Modul liegen.
- Schlüssel im `SharedStore` mit Präfix (`weather.…`).
- Was für alle Instanzen gilt (Listen, Zugangsdaten), gehört in die Config-App. Was pro Widget-Instanz verschieden sein darf (z. B. Filter, Zeitraum), gehört in den `WidgetConfigurationIntent`.

---

## Stock

Zeigt Kurse deiner ETFs und Aktien. Die Kurse kommen von **Lang & Schwarz**, dem Handelsplatz von Trade Republic. Es gibt keinen Login und keinen API-Key, und das Widget kennt dein Depot nicht. Es zeigt nur die Werte aus deiner Liste.

**Watchlist** (Config-App → Stock):
- **Hinzufügen:** nach Name, ISIN oder WKN suchen, dann auf **+ Hinzufügen** klicken
- **Kaufkurs:** pro Wert in € pro Stück eintragen. Er entscheidet über Grün oder Rot.
- **Löschen:** auf 🗑 klicken, per Rechtsklick → *Entfernen* oder mit der Entf-Taste
- **Sortieren:** Zeilen per Drag & Drop verschieben
- **Umbenennen:** auf den Namen klicken und tippen
- **Standardliste:** stellt die Werte aus dem Trade-Republic-Depot wieder her

**Jede Zeile im Widget:**

```
▲ MSCI World           ~~Tagesverlauf~~      126,78 €
  iShares Core MSCI World                   +28,28 €
```

- **Kurve:** standardmäßig der Tagesverlauf, umstellbar am Widget (1 Woche bis 5 Jahre). Die gestrichelte Linie zeigt den Vergleichskurs: Vortagesschluss bzw. Kurs zu Beginn des Zeitraums.
- **Rechts oben:** aktueller Kurs in €
- **Rechts unten:** Gewinn oder Verlust pro Stück seit Kauf in €
- **Farbe** von Pfeil, Kurve und Betrag: grün über dem Kaufkurs, rot darunter. Ohne Kaufkurs gilt die Veränderung zum Vergleichskurs.

**Am Widget** (Rechtsklick → bearbeiten):

| Option | Werte |
|---|---|
| Anzeigen | Alle · Nur ETFs · Nur Aktien |
| Zeitraum der Kurve | Heute · 1 Woche · 1 Monat · Seit Jahresbeginn · 1 Jahr · 5 Jahre |
| Nach Gewinn sortieren | an/aus (größter Gewinn seit Kauf oben) |

| Größe | Inhalt |
|---|---|
| Klein | 4 Werte: Name, Kurs, Gewinn/Verlust |
| Mittel | 4 Werte mit Tagesverlauf |
| Groß | 9 Werte mit Tagesverlauf |

Hinweise:
- Das Widget aktualisiert sich zur Handelszeit (Mo–Fr 7–23 Uhr) etwa alle 15 Minuten, sonst stündlich. macOS kann das strecken.
- Der Kaufkurs bleibt lokal auf deinem Mac (App Group) und wird nirgends hin übertragen.
- Die L&S-Schnittstelle ist nicht offiziell dokumentiert. Ändert sie sich, muss `StockFetcher` in `Shared/Stock/StockData.swift` angepasst werden.
