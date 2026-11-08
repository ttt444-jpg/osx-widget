# Stock-Widget: macOS-Widget für ETFs und Aktien

Zeigt die Kurse deiner Trade-Republic-Werte als Desktop-Widget. Die Kurse kommen von **Lang & Schwarz**, dem Handelsplatz von Trade Republic. Es gibt keinen Login und keinen API-Key, und das Widget kennt dein Depot nicht. Es zeigt nur die Werte, die du in die Liste einträgst.

```
stock-widget/
├── project.yml              ← XcodeGen-Projekt (App + Widget, gemeinsame App Group)
├── App/WatchApp.swift       ← Watchlist verwalten: suchen, hinzufügen, löschen, sortieren
├── Widget/WatchWidget.swift ← das Widget (klein / mittel / groß)
└── Shared/ETFData.swift     ← Datenmodell, Kursabruf, Speicher, Farben
```

## Bauen (einmalig, ca. 10 Minuten)

Voraussetzung: **Xcode** aus dem App Store, einmal gestartet, mit deiner Apple-ID unter *Xcode → Settings → Accounts*.

```bash
brew install xcodegen
cd ~/Documents/repos/osx-widget/stock-widget
xcodegen generate
open StockWidget.xcodeproj
```

1. In Xcode für **beide** Targets (`StockWidget` und `StockWidgetExtension`) unter *Signing & Capabilities* dein **Team** wählen. Die App Group (`<TeamID>.de.thomasdobler.stockwidget`) wird dann automatisch eingerichtet.
2. Scheme **StockWidget**, Ziel **My Mac**, dann **⌘R**.
3. Dauerhaft installieren: *Product → Archive → Distribute App → Custom → Copy App*, dann `Stock-Widget.app` nach **/Programme** ziehen und einmal starten.

## Benutzen

**Werte verwalten (App „Stock-Widget“):**
- **Hinzufügen:** oben nach Name, ISIN oder WKN suchen, dann auf **+ Hinzufügen** klicken
- **Löschen:** auf 🗑 klicken, per Rechtsklick → *Entfernen* oder mit der Entf-Taste
- **Sortieren:** Zeilen per Drag & Drop verschieben
- **Umbenennen:** auf den Namen klicken und tippen. Neue Werte heißen zunächst wie bei L&S („Ishsiii-Core Msci Wld Dla“), daher lohnt sich ein kurzer Name.
- **Standardliste:** stellt die 9 Werte aus deinem Depot wieder her

Jede Änderung landet sofort im Widget.

**Widget hinzufügen:** Rechtsklick auf den Schreibtisch → *Widgets bearbeiten* → **Stock-Widget** → Größe wählen.

**Widget einstellen** (Rechtsklick auf das Widget → *„Stock-Widget“ bearbeiten*):

| Option | Werte |
|---|---|
| Anzeigen | Alle · Nur ETFs · Nur Aktien |
| Zeitraum | Heute · 1 Woche · 1 Monat · Seit Jahresbeginn · 1 Jahr · 5 Jahre |
| Veränderung | in Euro · in Prozent |
| Nach Veränderung sortieren | an/aus |

Du kannst mehrere Widgets mit verschiedenen Einstellungen nebeneinanderstellen, z. B. groß mit allen Werten heute und mittel mit nur ETFs über 1 Jahr.

| Größe | Inhalt |
|---|---|
| Klein | 4 Werte: Name, Kurs, Veränderung |
| Mittel | 4 Werte mit Chart |
| Groß | 9 Werte mit Chart |

Jede Zeile: ▲/▼, Kurzname, voller Name, Chart mit gestrichelter Linie beim Vergleichskurs (Vortag bzw. Beginn des Zeitraums), Kurs und Veränderung.

## Hinweise

- Das Widget aktualisiert sich zur Handelszeit (Mo–Fr 7–23 Uhr) etwa alle 15 Minuten, sonst stündlich. macOS kann das strecken. Sofort neu laden: in der App auf **Widgets neu laden** klicken.
- Trade Republic zeigt in der Portfolio-Ansicht die Rendite **seit Kauf**. Das Widget zeigt die Veränderung im gewählten Zeitraum, weil es deine Kaufkurse nicht kennt.
- Die L&S-Schnittstelle ist nicht offiziell dokumentiert. Ändert sie sich, muss `ETFFetcher` in `Shared/ETFData.swift` angepasst werden.
