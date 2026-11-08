import AppIntents
import Charts
import SwiftUI
import WidgetKit

// MARK: - Einstellungen (Rechtsklick auf das Widget → „Widget bearbeiten“)
// Welche Werte drin sind, verwaltest du in der Config-App „OSX Widgets“ → Stock.

extension Period: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Zeitraum"
    static var caseDisplayRepresentations: [Period: DisplayRepresentation] = [
        .day: "Heute",
        .week: "1 Woche",
        .month: "1 Monat",
        .ytd: "Seit Jahresbeginn",
        .year: "1 Jahr",
        .fiveYears: "5 Jahre",
    ]
}

enum StockKindFilter: String, AppEnum {
    case all, etf, stock

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Anzeigen"
    static var caseDisplayRepresentations: [StockKindFilter: DisplayRepresentation] = [
        .all: "Alle",
        .etf: "Nur ETFs",
        .stock: "Nur Aktien",
    ]

    func matches(_ kind: AssetKind) -> Bool {
        switch self {
        case .all: true
        case .etf: kind == .etf
        case .stock: kind == .stock
        }
    }
}

struct StockConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Stock-Widget"
    static var description = IntentDescription("Werte und Kaufkurse: App „OSX Widgets“ → Stock.")

    @Parameter(title: "Anzeigen", default: .all)
    var filter: StockKindFilter

    @Parameter(title: "Zeitraum der Kurve", default: .day)
    var period: Period

    @Parameter(title: "Nach Gewinn sortieren", default: false)
    var sortByGain: Bool
}

// MARK: - Timeline

struct StockEntry: TimelineEntry {
    let date: Date
    let result: WatchResult
    let total: Int
}

struct StockProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StockEntry {
        StockEntry(date: .now, result: StockFetcher.sample, total: StockFetcher.sample.quotes.count)
    }

    func snapshot(for configuration: StockConfigIntent, in context: Context) async -> StockEntry {
        if context.isPreview { return placeholder(in: context) }
        return await load(configuration)
    }

    func timeline(for configuration: StockConfigIntent, in context: Context) async -> Timeline<StockEntry> {
        let entry = await load(configuration)
        // Während der Handelszeit alle 15 Minuten, sonst stündlich. macOS kann das strecken.
        let busy = entry.result.quotes.isEmpty || Self.marketOpen(.now)
        let next = Date().addingTimeInterval(busy ? 15 * 60 : 60 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    /// Handelszeit bei Lang & Schwarz für Trade Republic: Mo–Fr 7:30–23:00.
    static func marketOpen(_ date: Date) -> Bool {
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: date)  // 1 = Sonntag
        let hour = cal.component(.hour, from: date)
        return (2...6).contains(weekday) && (7..<23).contains(hour)
    }

    private func load(_ config: StockConfigIntent) async -> StockEntry {
        let items = StockStore.load().filter { config.filter.matches($0.kind) }
        var result = await StockFetcher.fetchAll(items, period: config.period)
        if config.sortByGain {
            result = WatchResult(
                quotes: result.quotes.sorted { ($0.gain ?? -.infinity) > ($1.gain ?? -.infinity) },
                failed: result.failed, date: result.date
            )
        }
        return StockEntry(date: .now, result: result, total: items.count)
    }
}

// MARK: - Widget

struct StockWidget: Widget {
    let kind = StockStore.kind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: StockConfigIntent.self, provider: StockProvider()) { entry in
            StockEntryView(entry: entry)
                .containerBackground(for: .widget) { Theme.bg }
        }
        .configurationDisplayName("Stock-Widget")
        .description("Kurse deiner ETFs und Aktien, wie bei Trade Republic (Lang & Schwarz).")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StockEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StockEntry

    /// So viele Zeilen passen in die jeweilige Größe.
    private var rows: Int {
        switch family {
        case .systemSmall: 4
        case .systemMedium: 4
        default: 9
        }
    }

    var body: some View {
        Group {
            if entry.result.quotes.isEmpty {
                StockErrorView(entry: entry)
            } else {
                VStack(spacing: 0) {
                    let quotes = Array(entry.result.quotes.prefix(rows))
                    ForEach(Array(quotes.enumerated()), id: \.element.id) { i, q in
                        if family == .systemSmall {
                            StockSmallRow(q: q)
                        } else {
                            StockRow(q: q)
                        }
                        if i < quotes.count - 1 {
                            Rectangle().fill(Theme.text.opacity(0.14)).frame(height: 1)
                        }
                    }
                    if quotes.count < rows { Spacer(minLength: 0) }
                }
            }
        }
        .foregroundStyle(Theme.text)
    }
}

// MARK: - Zeilen

/// Eine Zeile wie in der Aktien-App:
/// ▼ Name           ~~Kurve~~      ± seit Kauf %
///   voller Name                        Kurs €
/// Prozent und Grün/Rot beziehen sich auf den Kaufkurs (ohne Kaufkurs: auf den Vergleichskurs).
struct StockRow: View {
    let q: StockQuote

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    StockTrendArrow(change: q.gain, size: 9)
                    Text(q.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
                Text(q.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StockSparkline(values: q.points, reference: q.reference, color: Theme.trend(q.gain))
                .frame(width: 64)
                .padding(.vertical, 5)

            VStack(alignment: .trailing, spacing: 1) {
                Text(StockFmt.percent(q.gain))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.trend(q.gain))
                Text(StockFmt.price(q.price))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            .frame(minWidth: 72, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Kompakte Zeile ohne Kurve für das kleine Widget.
struct StockSmallRow: View {
    let q: StockQuote

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    StockTrendArrow(change: q.gain, size: 7)
                    Text(q.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                Text(StockFmt.price(q.price))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 2)
            Text(StockFmt.percent(q.gain))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.trend(q.gain))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Bausteine

struct StockTrendArrow: View {
    let change: Double?
    let size: CGFloat

    private var symbol: String {
        guard let change, abs(change) >= 0.00005 else { return "minus" }
        return change > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
    }

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Theme.trend(change))
    }
}

/// Kursverlauf mit Fläche darunter und gestrichelter Linie beim Vergleichskurs.
struct StockSparkline: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let values: [Double]
    let reference: Double?
    let color: Color

    var body: some View {
        let all = values + (reference.map { [$0] } ?? [])
        if values.count > 1, let lo = all.min(), let hi = all.max() {
            // Mindestens 1 % des Kurses als Höhe, sonst wirken Cent-Bewegungen wie Sprünge
            // und flache Kurse füllen das ganze Chart.
            let mid = (lo + hi) / 2
            let span = max(hi - lo, abs(mid) * 0.01, 0.0001) * 1.15
            let floor = mid - span / 2
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    // Im Monochrom-Modus („Vibrant“) wird die Fläche zum grauen Block, daher nur in Farbe.
                    if renderingMode == .fullColor {
                        AreaMark(x: .value("t", i), yStart: .value("min", floor), yEnd: .value("Kurs", v))
                            .foregroundStyle(
                                LinearGradient(colors: [color.opacity(0.45), color.opacity(0)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                    }
                    LineMark(x: .value("t", i), y: .value("Kurs", v))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
                if let reference {
                    RuleMark(y: .value("Vergleich", reference))
                        .foregroundStyle(Theme.muted.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartXScale(domain: 0...(values.count - 1))
            .chartYScale(domain: floor...(floor + span))
        } else {
            Color.clear
        }
    }
}

struct StockErrorView: View {
    let entry: StockEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stock-Widget")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
            Text(entry.total == 0 ? "Keine Werte" : "Keine Kurse")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.red)
            Text(entry.total == 0
                 ? "Öffne „OSX Widgets“ → Stock und füge ETFs oder Aktien hinzu."
                 : "Lang & Schwarz nicht erreichbar. Neuer Versuch in 15 Minuten.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
