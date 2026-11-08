# osx-widget

Native macOS-Desktop-Widgets (SwiftUI + WidgetKit).

| Ordner | Widget | Anleitung |
|---|---|---|
| [`stock-widget/`](stock-widget) | **Stock-Widget**: Kurse von ETFs und Aktien wie bei Trade Republic (Lang & Schwarz), Watchlist in der App verwaltbar | [stock-widget/ANLEITUNG.md](stock-widget/ANLEITUNG.md) |
| [`mac/`](mac), [`server/`](server) | **Server-Status**: Websites, Dienste, Container und Ressourcen eines Servers über eine kleine Status-API | [ANLEITUNG.md](ANLEITUNG.md) |

## Bauen

Voraussetzung: Xcode und [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cd stock-widget   # oder: cd mac
xcodegen generate
open *.xcodeproj
```

In Xcode für beide Targets das Signing-Team setzen, dann ⌘R.
