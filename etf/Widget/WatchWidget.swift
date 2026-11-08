import AppIntents
import Charts
import SwiftUI
import WidgetKit

// MARK: - Einstellungen (Rechtsklick auf das Widget → „Widget bearbeiten“)
// Welche Werte drin sind, verwaltest du in der App „Depot-Kurse“.

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

enum KindFilter: String, AppEnum {
    case all, etf, stock

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Anzeigen"
    static var caseDisplayRepresentations: [KindFilter: DisplayRepresentation] = [
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

enum ChangeStyle: String, AppEnum {
    case absolute, percent

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Veränderung"
    static var caseDisplayRepresentations: [ChangeStyle: DisplayRepresentation] = [
        .absolute: "in Euro",
        .percent: "in Prozent",
    ]
}

struct WatchConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Depot-Kurse"
    static var description = IntentDescription("Werte hinzufügen oder löschen: App „Depot-Kurse“ öffnen.")

    @Parameter(title: "Anzeigen", default: .all)
    var filter: KindFilter

    @Parameter(title: "Zeitraum", default: .day)
    var period: Period

    @Parameter(title: "Veränderung", default: .absolute)
    var changeStyle: ChangeStyle

    @Parameter(title: "Nach Veränderung sortieren", default: false)
    var sortByChange: Bool
}

// MARK: - Timeline

struct WatchEntry: TimelineEntry {
    let date: Date
    let result: WatchResult
    let style: ChangeStyle
    let total: Int
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: .now, result: ETFFetcher.sample, style: .absolute, total: ETFFetcher.sample.quotes.count)
    }

    func snapshot(for configuration: WatchConfigIntent, in context: Context) async -> WatchEntry {
        if context.isPreview { return placeholder(in: context) }
        return await load(configuration)
    }

    func timeline(for configuration: WatchConfigIntent, in context: Context) async -> Timeline<WatchEntry> {
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

    private func load(_ config: WatchConfigIntent) async -> WatchEntry {
        let items = WatchStore.load().filter { config.filter.matches($0.kind) }
        var result = await ETFFetcher.fetchAll(items, period: config.period)
        if config.sortByChange {
            result = WatchResult(
                quotes: result.quotes.sorted { ($0.change ?? -.infinity) > ($1.change ?? -.infinity) },
                failed: result.failed, period: result.period, date: result.date
            )
        }
        return WatchEntry(date: .now, result: result, style: config.changeStyle, total: items.count)
    }
}

// MARK: - Widget

@main
struct WatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchWidget()
    }
}

struct WatchWidget: Widget {
    let kind = "DepotKurseWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WatchConfigIntent.self, provider: Provider()) { entry in
            EntryView(entry: entry)
                .containerBackground(for: .widget) { Theme.bg }
        }
        .configurationDisplayName("Depot-Kurse")
        .description("Kurse deiner ETFs und Aktien, wie bei Trade Republic (Lang & Schwarz).")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct EntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

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
                ErrorView(entry: entry)
            } else {
                VStack(spacing: 0) {
                    let quotes = Array(entry.result.quotes.prefix(rows))
                    ForEach(Array(quotes.enumerated()), id: \.element.id) { i, q in
                        if family == .systemSmall {
                            SmallRow(q: q, style: entry.style)
                        } else {
                            QuoteRow(q: q, style: entry.style, period: entry.result.period)
                        }
                        if i < quotes.count - 1 {
                            Rectangle().fill(Theme.divider).frame(height: 0.5)
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
/// ▼ Name           ~~Chart~~      Kurs
///   voller Name                Veränderung
struct QuoteRow: View {
    let q: ETFQuote
    let style: ChangeStyle
    let period: Period

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    TrendArrow(change: q.change, size: 9)
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

            Sparkline(values: q.points, reference: q.reference, color: Theme.trend(q.change))
                .frame(width: 70)
                .padding(.vertical, 5)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.number(q.price))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                Text(changeText(q, style))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.trend(q.change))
            }
            .frame(minWidth: 62, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
    }
}

/// Kompakte Zeile ohne Chart für das kleine Widget.
struct SmallRow: View {
    let q: ETFQuote
    let style: ChangeStyle

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    TrendArrow(change: q.change, size: 7)
                    Text(q.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                Text(Fmt.number(q.price))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 2)
            Text(changeText(q, style))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.trend(q.change))
        }
        .frame(maxHeight: .infinity)
    }
}

private func changeText(_ q: ETFQuote, _ style: ChangeStyle) -> String {
    style == .percent ? Fmt.percent(q.change) : Fmt.delta(q.changeAbs)
}

// MARK: - Bausteine

struct TrendArrow: View {
    let change: Double?
    let size: CGFloat

    var body: some View {
        Image(systemName: (change ?? 0) >= 0 ? "arrowtriangle.up.fill" :"arrowtriangle.down.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Theme.trend(change))
    }
}

/// Verlauf mit Fläche darunter und gestrichelter Linie beim Vergleichskurs.
struct Sparkline: View {
    let values: [Double]
    let reference: Double?
    let color: Color

    var body: some View {
        let all = values + (reference.map { [$0] } ?? [])
        if values.count > 1, let lo = all.min(), let hi = all.max() {
            let pad = (hi - lo) * 0.08 + 0.0001
            let floor = lo - pad
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("t", i), yStart: .value("min", floor), yEnd: .value("Kurs", v))
                        .foregroundStyle(
                            LinearGradient(colors: [color.opacity(0.45), color.opacity(0)],
                                           startPoint: .top, endPoint: .bottom)
                        )
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
            .chartYScale(domain: floor...(hi + pad))
        } else {
            Color.clear
        }
    }
}

struct ErrorView: View {
    let entry: WatchEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Depot-Kurse")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
            Text(entry.total == 0 ? "Keine Werte" : "Keine Kurse")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.red)
            Text(entry.total == 0
                 ? "Öffne die App „Depot-Kurse“ und füge ETFs oder Aktien hinzu."
                 : "Lang & Schwarz nicht erreichbar. Neuer Versuch in 15 Minuten.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
