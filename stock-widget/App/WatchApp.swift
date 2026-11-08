import SwiftUI
import WidgetKit

@main
struct WatchApp: App {
    var body: some Scene {
        WindowGroup("Stock-Widget") {
            ContentView()
                .frame(width: 560, height: 680)
        }
        .windowResizability(.contentSize)
    }
}

/// Watchlist verwalten: suchen und hinzufügen, löschen, sortieren, umbenennen.
/// Jede Änderung wird sofort gespeichert und die Widgets neu geladen.
struct ContentView: View {
    @State private var items: [WatchItem] = WatchStore.load()
    @State private var quotes: [String: ETFQuote] = [:]
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    @State private var searchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stock-Widget")
                .font(.title2.weight(.semibold))
            Text("Widget hinzufügen: Rechtsklick auf den Schreibtisch → „Widgets bearbeiten“ → Stock-Widget. Zeitraum, Filter und € oder % stellst du per Rechtsklick auf das Widget ein.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Suche
            HStack {
                TextField("ETF oder Aktie suchen: Name, ISIN oder WKN", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }
                Button(searching ? "Suche…" : "Suchen") { Task { await search() } }
                    .disabled(searching || query.count < 2)
            }
            if let searchError {
                Text(searchError).foregroundStyle(.red).font(.callout)
            }
            if !hits.isEmpty {
                List(hits) { hit in
                    HStack {
                        KindBadge(kind: hit.kind, label: hit.category)
                        VStack(alignment: .leading) {
                            Text(hit.name)
                            Text(hit.isin).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if items.contains(where: { $0.isin == hit.isin }) {
                            Text("in der Liste").foregroundStyle(.secondary).font(.callout)
                        } else {
                            Button { add(hit) } label: { Label("Hinzufügen", systemImage: "plus.circle.fill") }
                        }
                    }
                }
                .frame(height: 150)
                .listStyle(.bordered)
            }

            Divider()

            // Watchlist
            HStack {
                Text("Deine Liste (\(items.count))").font(.headline)
                Spacer()
                Button("Kurse aktualisieren") { Task { await loadQuotes() } }
            }
            List {
                ForEach($items) { $item in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        KindBadge(kind: item.kind, label: item.kind.title)
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Name", text: $item.name)
                                .textFieldStyle(.plain)
                                .font(.body.weight(.semibold))
                                .onSubmit { save() }
                            Text("\(item.detail) · \(item.isin)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let q = quotes[item.isin] {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(Fmt.price(q.price)).monospacedDigit()
                                Text(Fmt.percent(q.change)).monospacedDigit()
                                    .font(.caption)
                                    .foregroundStyle(Theme.trend(q.change))
                            }
                        }
                        Button(role: .destructive) { remove(item) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Aus der Liste entfernen")
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Entfernen", role: .destructive) { remove(item) }
                    }
                }
                .onMove { from, to in
                    items.move(fromOffsets: from, toOffset: to)
                    save()
                }
                .onDelete { offsets in
                    items.remove(atOffsets: offsets)
                    save()
                }
            }
            .listStyle(.bordered)

            HStack {
                Text("Reihenfolge per Drag & Drop, Namen per Klick umbenennen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Standardliste") {
                    items = ETFDefaults.watchlist
                    save()
                }
                Button("Widgets neu laden") { WidgetCenter.shared.reloadAllTimelines() }
            }
        }
        .padding(20)
        .task { await loadQuotes() }
        .onChange(of: items.map(\.name)) { _, _ in save() }
    }

    private func search() async {
        searching = true
        searchError = nil
        defer { searching = false }
        do {
            hits = try await ETFFetcher.search(query)
            if hits.isEmpty { searchError = "Nichts gefunden." }
        } catch {
            searchError = error.localizedDescription
        }
    }

    private func add(_ hit: SearchHit) {
        let item = WatchItem(isin: hit.isin, name: hit.name, detail: hit.detail, kind: hit.kind)
        items.append(item)
        save()
        Task {
            if let q = try? await ETFFetcher.fetch(item, period: .day) { quotes[q.isin] = q }
        }
    }

    private func remove(_ item: WatchItem) {
        items.removeAll { $0.isin == item.isin }
        save()
    }

    private func save() {
        WatchStore.save(items)
    }

    private func loadQuotes() async {
        let result = await ETFFetcher.fetchAll(items, period: .day)
        quotes = Dictionary(uniqueKeysWithValues: result.quotes.map { ($0.isin, $0) })
    }
}

struct KindBadge: View {
    let kind: AssetKind
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minWidth: 44)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch kind {
        case .etf: .blue
        case .stock: .purple
        case .other: .gray
        }
    }
}
