import SwiftUI
import WidgetKit

@main
struct ConfigApp: App {
    var body: some Scene {
        WindowGroup("OSX Widgets") {
            RootView()
                // Inhalt füllt das Fenster. Achtung in Einstellungsseiten: kein
                // .fixedSize(vertical: true) auf langen Texten – siehe README „Konventionen“.
                .frame(minWidth: 760, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        }
        .defaultSize(width: 900, height: 720)
    }
}

// MARK: - Widget-Verzeichnis

/// Ein Eintrag in der Seitenleiste der Config-App.
/// Neues Widget: hier eine Zeile ergänzen (siehe README → „Neues Widget hinzufügen“).
struct WidgetModule: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let subtitle: String

    static let all: [WidgetModule] = [
        WidgetModule(id: "stock", title: "Stock", icon: "chart.line.uptrend.xyaxis",
                     subtitle: "ETF- und Aktienkurse"),
    ]

    @ViewBuilder
    var settings: some View {
        switch id {
        case "stock": StockSettingsView()
        default: Text("Keine Einstellungen").foregroundStyle(.secondary)
        }
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// MARK: - Hauptfenster

struct RootView: View {
    @State private var selection: WidgetModule.ID? = WidgetModule.all.first?.id

    var body: some View {
        NavigationSplitView {
            List(WidgetModule.all, selection: $selection) { module in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(module.title)
                        Text(module.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: module.icon)
                }
                .tag(module.id)
                .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) {
                Button {
                    WidgetCenter.shared.reloadAllTimelines()
                } label: {
                    Label("Alle Widgets neu laden", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .padding(12)
            }
        } detail: {
            if let module = WidgetModule.all.first(where: { $0.id == selection }) {
                module.settings
            } else {
                Text("Widget in der Seitenleiste wählen").foregroundStyle(.secondary)
            }
        }
    }
}
