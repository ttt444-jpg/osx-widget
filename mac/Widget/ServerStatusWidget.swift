import AppIntents
import Charts
import SwiftUI
import WidgetKit

// MARK: - Einstellungen (Rechtsklick auf das Widget → „Widget bearbeiten“)

struct ServerConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Server"
    static var description = IntentDescription("Status-Endpunkt deines Servers")

    @Parameter(title: "Name", default: "diedoblers")
    var name: String

    @Parameter(title: "Status-URL", default: "https://status.example.de/status")
    var url: String

    @Parameter(title: "Token", default: "")
    var token: String
}

// MARK: - Timeline

struct StatusEntry: TimelineEntry {
    let date: Date
    let name: String
    let status: ServerStatus?
    let error: String?
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, name: "diedoblers", status: StatusFetcher.sample, error: nil)
    }

    func snapshot(for configuration: ServerConfigIntent, in context: Context) async -> StatusEntry {
        if context.isPreview { return placeholder(in: context) }
        return await load(configuration)
    }

    func timeline(for configuration: ServerConfigIntent, in context: Context) async -> Timeline<StatusEntry> {
        let entry = await load(configuration)
        // macOS begrenzt die Aktualisierungen; 15 Minuten sind realistisch.
        let next = Date().addingTimeInterval(entry.status == nil ? 5 * 60 : 15 * 60)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func load(_ config: ServerConfigIntent) async -> StatusEntry {
        do {
            let status = try await StatusFetcher.fetch(url: config.url, token: config.token)
            return StatusEntry(date: .now, name: config.name, status: status, error: nil)
        } catch {
            return StatusEntry(date: .now, name: config.name, status: nil,
                               error: error.localizedDescription)
        }
    }
}

// MARK: - Widget

@main
struct ServerStatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        ServerStatusWidget()
    }
}

struct ServerStatusWidget: Widget {
    let kind = "ServerStatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ServerConfigIntent.self, provider: Provider()) { entry in
            EntryView(entry: entry)
                .containerBackground(for: .widget) { Theme.bg }
        }
        .configurationDisplayName("Server-Status")
        .description("Websites, Dienste, Container und Ressourcen auf einen Blick.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct EntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    var body: some View {
        Group {
            if let status = entry.status {
                switch family {
                case .systemSmall: SmallView(name: entry.name, s: status)
                case .systemMedium: MediumView(name: entry.name, s: status)
                default: LargeView(name: entry.name, s: status)
                }
            } else {
                ErrorView(name: entry.name, message: entry.error ?? "Keine Daten")
            }
        }
        .foregroundStyle(Theme.text)
    }
}

// MARK: - Größen

struct SmallView: View {
    let name: String
    let s: ServerStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(name: name, health: s.health)
            Spacer(minLength: 0)
            Text(s.problems.isEmpty ? s.health.title : "\(s.problems.count) Problem\(s.problems.count == 1 ? "" : "e")")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(s.health == .ok ? Theme.text : s.health.color)
            Text(s.problems.first ?? "Stand \(s.generatedDate.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                MiniCount(label: "Web", count: s.websites)
                Spacer(minLength: 4)
                MiniCount(label: "Dienste", count: s.services)
                Spacer(minLength: 4)
                MiniCount(label: "Ctr", count: s.containers)
            }
        }
    }
}

struct MediumView: View {
    let name: String
    let s: ServerStatus

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Header(name: name, health: s.health)
                Text(s.problems.first ?? s.health.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(s.health == .ok ? Theme.text : s.health.color)
                    .lineLimit(2)
                Spacer(minLength: 0)
                CountRow(label: "Websites", count: s.websites)
                CountRow(label: "Dienste", count: s.services)
                CountRow(label: "Container", count: s.containers)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                MetricSpark(label: "CPU", value: s.resources?.cpu, values: s.history?.cpu ?? [], color: Theme.green)
                MetricSpark(label: "RAM", value: s.resources?.ram, values: s.history?.ram ?? [], color: Theme.blue)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct LargeView: View {
    let name: String
    let s: ServerStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Header(name: name, health: s.health)
                Spacer()
                Text(s.generatedDate.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }

            Text(s.problems.isEmpty ? s.health.title : s.problems.joined(separator: " · "))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(s.health == .ok ? Theme.text : s.health.color)
                .lineLimit(2)

            HStack(spacing: 8) {
                Tile(label: "Websites", value: s.websites?.text ?? "–", ok: s.websites?.ok)
                Tile(label: "Dienste", value: s.services?.text ?? "–", ok: s.services?.ok)
                Tile(label: "Container", value: s.containers?.text ?? "–", ok: s.containers?.ok)
                Tile(label: "Alarme", value: (s.alerts ?? 0) == 0 ? "keine" : "\(s.alerts ?? 0)", ok: (s.alerts ?? 0) == 0)
            }

            HStack(spacing: 12) {
                Ring(label: "Zertifikat", value: s.certMinDays.map(Double.init), max: 90, text: s.certMinDays.map { "\($0) d" },
                     color: certColor)
                Ring(label: "Lynis", value: s.lynis.map(Double.init), max: 100, text: s.lynis.map { "\($0)" },
                     color: Theme.blue)
                VStack(alignment: .leading, spacing: 5) {
                    InfoRow(label: "Updates", value: patchText)
                    InfoRow(label: "Neustart", value: (s.patches?.rebootRequired ?? false) ? "nötig" : "nein",
                            color: (s.patches?.rebootRequired ?? false) ? Theme.yellow : nil)
                    InfoRow(label: "fail2ban", value: s.fail2banBanned.map { "\($0) gesperrt" } ?? "–", color: Theme.blue)
                    InfoRow(label: "Scrape-Job", value: scrapeText,
                            color: (s.scrape?.ok == false) ? Theme.red : nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                MetricSpark(label: "CPU", value: s.resources?.cpu, values: s.history?.cpu ?? [], color: Theme.green)
                MetricSpark(label: "RAM", value: s.resources?.ram, values: s.history?.ram ?? [], color: Theme.blue)
            }

            HStack(spacing: 8) {
                SmallStat(label: "Platte", value: s.resources?.disk.map { "\(Int($0)) %" })
                SmallStat(label: "Swap", value: s.resources?.swap.map { "\(Int($0)) %" })
                SmallStat(label: "Load", value: s.resources?.load5.map { String(format: "%.2f", $0) })
                SmallStat(label: "Uptime", value: s.resources?.uptimeDays.map { String(format: "%.0f d", $0) })
            }
        }
    }

    private var certColor: Color {
        guard let d = s.certMinDays else { return Theme.muted }
        return d < 14 ? Theme.red : d < 30 ? Theme.yellow : Theme.green
    }

    private var patchText: String {
        guard let p = s.patches else { return "–" }
        let u = p.updates ?? 0, sec = p.security ?? 0
        if u == 0 { return "aktuell" }
        return sec > 0 ? "\(u) (\(sec) Sicherheit)" : "\(u) offen"
    }

    private var scrapeText: String {
        guard let sc = s.scrape, let ok = sc.ok else { return "–" }
        let src = (sc.sourcesOk != nil && sc.sourcesTotal != nil) ? " \(sc.sourcesOk!)/\(sc.sourcesTotal!)" : ""
        return (ok ? "OK" : "Fehler") + src
    }
}

struct ErrorView: View {
    let name: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(name: name, health: .unknown)
            Spacer(minLength: 0)
            Text("Nicht erreichbar")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            Text("Rechtsklick → Widget bearbeiten")
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Bausteine

struct Header: View {
    let name: String
    let health: Health

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(health.color)
                .frame(width: 8, height: 8)
                .shadow(color: health.color.opacity(0.8), radius: 4)
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
        }
    }
}

struct MiniCount: View {
    let label: String
    let count: ServerStatus.Count?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(count?.text ?? "–")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(count.map { $0.ok ? Theme.text : Theme.red } ?? Theme.muted)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Theme.muted)
        }
    }
}

struct CountRow: View {
    let label: String
    let count: ServerStatus.Count?

    var body: some View {
        HStack {
            Circle()
                .fill(count.map { $0.ok ? Theme.green : Theme.red } ?? Theme.muted)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(count?.text ?? "–")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
    }
}

struct Tile: View {
    let label: String
    let value: String
    let ok: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(ok == false ? Theme.red : Theme.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct Ring: View {
    let label: String
    let value: Double?
    let max: Double
    let text: String?
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(1, (value ?? 0) / max))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(text ?? "–")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .frame(width: 54, height: 54)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var color: Color? = nil

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color ?? Theme.text)
                .lineLimit(1)
        }
    }
}

struct SmallStat: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
            Text(value ?? "–")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MetricSpark: View {
    let label: String
    let value: Double?
    let values: [Double]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(value.map { "\(Int($0.rounded())) %" } ?? "–")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            Sparkline(values: values, color: color)
                .frame(maxHeight: .infinity)
        }
        .padding(8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { point in
            AreaMark(x: .value("t", point.offset), y: .value("v", point.element))
                .foregroundStyle(color.opacity(0.18))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("t", point.offset), y: .value("v", point.element))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
    }
}

// MARK: - Vorschau in Xcode

#Preview(as: .systemLarge) {
    ServerStatusWidget()
} timeline: {
    StatusEntry(date: .now, name: "diedoblers", status: StatusFetcher.sample, error: nil)
}
