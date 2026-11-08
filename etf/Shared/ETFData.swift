import Foundation
import SwiftUI
import WidgetKit

// MARK: - Watchlist

enum AssetKind: String, Codable, CaseIterable {
    case etf, stock, other

    var title: String {
        switch self {
        case .etf: "ETF"
        case .stock: "Aktie"
        case .other: "Sonstige"
        }
    }

    /// Kategorie aus der L&S-Suche („ETF“, „Aktie“, „Fonds“, …).
    init(lsCategory: String) {
        switch lsCategory.lowercased() {
        case "etf", "etc", "etn": self = .etf
        case "aktie": self = .stock
        default: self = .other
        }
    }
}

struct WatchItem: Codable, Hashable, Identifiable {
    let isin: String
    /// Kurzname, fett in der Zeile (z. B. „MSCI World“).
    var name: String
    /// Voller Name, grau darunter (z. B. „iShares Core MSCI World“).
    var detail: String
    var kind: AssetKind

    var id: String { isin }
}

enum ETFDefaults {
    /// ETFs und Aktien aus dem Trade-Republic-Depot, in der Reihenfolge der App.
    static let watchlist: [WatchItem] = [
        WatchItem(isin: "IE00B57X3V84", name: "DJ Sustainability", detail: "iShares DJ Global Sustainability Screened", kind: .etf),
        WatchItem(isin: "US8740541094", name: "Take-Two", detail: "Take-Two Interactive Software", kind: .stock),
        WatchItem(isin: "IE00B4L5Y983", name: "MSCI World", detail: "iShares Core MSCI World", kind: .etf),
        WatchItem(isin: "US67066G1040", name: "NVIDIA", detail: "NVIDIA Corp.", kind: .stock),
        WatchItem(isin: "IE000I8KRLL9", name: "Semiconductors", detail: "iShares MSCI Global Semiconductors", kind: .etf),
        WatchItem(isin: "IE00B5BMR087", name: "S&P 500", detail: "iShares Core S&P 500", kind: .etf),
        WatchItem(isin: "IE00BK5BQT80", name: "FTSE All-World", detail: "Vanguard FTSE All-World", kind: .etf),
        WatchItem(isin: "IE00BKM4GZ66", name: "MSCI EM IMI", detail: "iShares Core MSCI EM IMI", kind: .etf),
        WatchItem(isin: "CA22587M1068", name: "Cresco Labs", detail: "Cresco Labs Inc.", kind: .stock),
    ]

    /// Lesbare Namen für bekannte ETFs statt der L&S-Kürzel („ISHSIII-CORE MSCI WLD DLA“).
    static let names: [String: String] = [
        "IE00B3RBWM25": "FTSE All-World Dist",
        "IE00B53SZB19": "Nasdaq 100",
        "IE00BF4RFH31": "MSCI World Small Cap",
        "IE00BFY0GT14": "MSCI World (SPDR)",
        "IE00BJ0KDQ92": "MSCI World (Xtrackers)",
        "LU0274208692": "MSCI World Swap",
        "IE00B4K48X80": "MSCI Europe",
        "DE0005933931": "DAX",
        "IE00BYZK4552": "Automation & Robotics",
        "IE00B3WJKG14": "S&P 500 IT",
        "IE00BZ163G84": "EUR Corp Bonds",
    ]

    /// Macht aus „NVIDIA CORP.      DL-,001“ ein lesbares „Nvidia Corp.“.
    static func prettyName(isin: String, lsName: String) -> String {
        names[isin] ?? cleanName(lsName)
    }

    static func cleanName(_ lsName: String) -> String {
        let cut = lsName.components(separatedBy: "  ").first ?? lsName
        let cleaned = cut
            .replacingOccurrences(of: #"\s+(DL|EO|SF|LS|CD)-?[,.\d]*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.capitalized
    }
}

// MARK: - Gemeinsamer Speicher von App und Widget (App Group)

enum WatchStore {
    private static let key = "watchlist.v1"

    /// Kommt aus der Info.plist (`AppGroupID`), damit die Team-ID nicht im Code steht.
    static var groupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
    }

    private static var defaults: UserDefaults {
        groupID.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    static func load() -> [WatchItem] {
        guard let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([WatchItem].self, from: data)
        else { return ETFDefaults.watchlist }
        return items
    }

    static func save(_ items: [WatchItem]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Zeitraum

enum Period: String, CaseIterable, Codable, Sendable {
    case day, week, month, ytd, year, fiveYears

    var short: String {
        switch self {
        case .day: "Heute"
        case .week: "1W"
        case .month: "1M"
        case .ytd: "YTD"
        case .year: "1J"
        case .fiveYears: "5J"
        }
    }

    /// Beginn des Zeitraums; `nil` heißt „seit Vortagesschluss“.
    func start(from now: Date) -> Date? {
        let cal = Calendar(identifier: .gregorian)
        switch self {
        case .day: return nil
        case .week: return cal.date(byAdding: .day, value: -7, to: now)
        case .month: return cal.date(byAdding: .month, value: -1, to: now)
        case .ytd: return cal.date(from: cal.dateComponents([.year], from: now))
        case .year: return cal.date(byAdding: .year, value: -1, to: now)
        case .fiveYears: return cal.date(byAdding: .year, value: -5, to: now)
        }
    }
}

// MARK: - Kurs

struct ETFQuote: Identifiable, Hashable {
    let isin: String
    let name: String
    let detail: String
    let kind: AssetKind
    let price: Double
    /// Kurs zu Beginn des Zeitraums (bei „Heute“: Vortagesschluss).
    let reference: Double?
    /// Kursverlauf im Zeitraum, für die Sparkline.
    let points: [Double]
    let updated: Date

    var id: String { isin }
    var change: Double? { reference.map { price / $0 - 1 } }
    var changeAbs: Double? { reference.map { price - $0 } }
}

struct WatchResult {
    let quotes: [ETFQuote]
    let failed: [String]
    let period: Period
    let date: Date

    /// Durchschnittliche Veränderung, gleich gewichtet.
    var averageChange: Double? {
        let c = quotes.compactMap(\.change)
        return c.isEmpty ? nil : c.reduce(0, +) / Double(c.count)
    }
}

struct SearchHit: Identifiable, Hashable {
    let isin: String
    let name: String
    let detail: String
    let kind: AssetKind
    let category: String
    var id: String { isin }
}

// MARK: - Abruf bei Lang & Schwarz (dort handelt Trade Republic)

enum ETFFetcher {
    private static let base = "https://www.ls-tc.de/_rpc/json"

    enum FetchError: LocalizedError {
        case notFound(String)
        case http(Int)
        case noData(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let isin): "ISIN \(isin) nicht gefunden"
            case .http(let code): "HTTP \(code)"
            case .noData(let isin): "Keine Kurse für \(isin)"
            }
        }
    }

    private struct LSHit: Decodable {
        let instrumentId: Int
        let displayname: String
        let isin: String
        let categoryName: String?
    }

    private struct ChartResponse: Decodable {
        struct Info: Decodable {
            struct Plotline: Decodable {
                let id: String?
                let value: Double?
            }
            let plotlines: [Plotline]?
        }
        struct Series: Decodable {
            let data: [[Double?]]?
        }
        let info: Info?
        let series: [String: Series]?
    }

    private struct Point {
        let date: Date
        let price: Double
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Suche nach Name, ISIN oder WKN.
    static func search(_ query: String) async throws -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }

        func raw(_ text: String) async throws -> [LSHit] {
            guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return [] }
            return try await get(".lstc/instrument/search/main?q=\(encoded)&localeId=2")
        }
        func words(_ text: String) -> [String] {
            text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }

        var hits = try await raw(q)
        // L&S sucht nur Teilstrings: „nasdaq 100“ findet „NASDAQ-100“ nicht.
        // Dann mit dem längsten Wort suchen und auf alle Wörter filtern.
        let tokens = words(q)
        if hits.isEmpty, tokens.count > 1, let longest = tokens.max(by: { $0.count < $1.count }) {
            hits = try await raw(longest).filter { hit in
                let name = words(hit.displayname)
                return tokens.allSatisfy { t in name.contains { $0.hasPrefix(t) } }
            }
        }
        var seen = Set<String>()
        return hits.compactMap { hit in
            guard !hit.isin.isEmpty, seen.insert(hit.isin).inserted else { return nil }
            cacheID(hit)
            let category = hit.categoryName ?? ""
            return SearchHit(isin: hit.isin,
                             name: ETFDefaults.prettyName(isin: hit.isin, lsName: hit.displayname),
                             detail: ETFDefaults.cleanName(hit.displayname),
                             kind: AssetKind(lsCategory: category),
                             category: category)
        }
    }

    /// Alle Werte parallel laden; die Reihenfolge der Watchlist bleibt erhalten.
    static func fetchAll(_ items: [WatchItem], period: Period) async -> WatchResult {
        let results = await withTaskGroup(of: (Int, ETFQuote?).self) { group in
            for (i, item) in items.enumerated() {
                group.addTask { (i, try? await fetch(item, period: period)) }
            }
            var out = [(Int, ETFQuote?)]()
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }
        }
        let quotes = results.compactMap(\.1)
        let failed = results.filter { $0.1 == nil }.map { items[$0.0].name }
        return WatchResult(quotes: quotes, failed: failed, period: period, date: .now)
    }

    static func fetch(_ item: WatchItem, period: Period) async throws -> ETFQuote {
        let id = try await lookup(item.isin)
        let chart: ChartResponse = try await get("instrument/chart/dataForInstrument?instrumentId=\(id)")

        func points(_ key: String) -> [Point] {
            (chart.series?[key]?.data ?? []).compactMap { row in
                guard row.count >= 2, let t = row[0], let p = row[1] else { return nil }
                return Point(date: Date(timeIntervalSince1970: t / 1000), price: p)
            }
        }
        let intraday = points("intraday")
        let history = points("history")
        guard let last = intraday.last ?? history.last else { throw FetchError.noData(item.isin) }

        let reference: Double?
        var series: [Double]
        if let start = period.start(from: .now) {
            let slice = history.filter { $0.date >= start }
            reference = history.last(where: { $0.date <= start })?.price ?? slice.first?.price
            series = slice.map(\.price)
        } else {
            let prevClose = chart.info?.plotlines?.first(where: { $0.id == "previousDay" })?.value
            reference = prevClose ?? history.dropLast().last?.price
            series = intraday.map(\.price)
            if let ref = reference { series.insert(ref, at: 0) }
        }
        if series.last != last.price { series.append(last.price) }

        return ETFQuote(
            isin: item.isin,
            name: item.name,
            detail: item.detail,
            kind: item.kind,
            price: last.price,
            reference: reference,
            points: downsample(series, to: 90),
            updated: last.date
        )
    }

    // ISIN → Instrument-ID bei L&S. Die IDs ändern sich nicht, daher Cache.
    private static func idKey(_ isin: String) -> String { "ls.id.\(isin)" }

    private static func cacheID(_ hit: LSHit) {
        UserDefaults.standard.set(hit.instrumentId, forKey: idKey(hit.isin))
    }

    private static func lookup(_ isin: String) async throws -> Int {
        if let id = UserDefaults.standard.object(forKey: idKey(isin)) as? Int { return id }
        let hits: [LSHit] = try await get(".lstc/instrument/search/main?q=\(isin)&localeId=2")
        guard let hit = hits.first(where: { $0.isin == isin }) else { throw FetchError.notFound(isin) }
        cacheID(hit)
        return hit.instrumentId
    }

    private static func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: URL(string: "\(base)/\(path)")!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FetchError.http(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func downsample(_ values: [Double], to max: Int) -> [Double] {
        guard values.count > max else { return values }
        let step = Double(values.count - 1) / Double(max - 1)
        return (0..<max).map { values[Int((Double($0) * step).rounded())] }
    }

    static let sample = WatchResult(
        quotes: [
            ETFQuote(isin: "IE00B4L5Y983", name: "MSCI World", detail: "MSCI World", kind: .etf, price: 126.78, reference: 125.90,
                     points: [125.9, 126.1, 125.8, 126.3, 126.5, 126.4, 126.78], updated: .now),
            ETFQuote(isin: "US67066G1040", name: "NVIDIA", detail: "NVIDIA", kind: .stock, price: 170.14, reference: 169.34,
                     points: [169.3, 169.9, 169.5, 170.4, 170.0, 170.14], updated: .now),
            ETFQuote(isin: "IE00B5BMR087", name: "S&P 500", detail: "S&P 500", kind: .etf, price: 642.10, reference: 636.55,
                     points: [636.5, 638.0, 637.2, 640.4, 641.0, 642.1], updated: .now),
            ETFQuote(isin: "IE00BKM4GZ66", name: "MSCI EM IMI", detail: "MSCI EM IMI", kind: .etf, price: 39.12, reference: 39.40,
                     points: [39.4, 39.3, 39.35, 39.2, 39.1, 39.12], updated: .now),
        ],
        failed: [], period: .day, date: .now
    )
}

// MARK: - Formatierung

enum Fmt {
    private static let de = Locale(identifier: "de_DE")

    static func price(_ v: Double) -> String {
        v.formatted(.currency(code: "EUR").locale(de))
    }

    /// Kurs ohne Währung, wie in der Aktien-App: „126,78“.
    static func number(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(2)).locale(de))
    }

    /// Absolute Veränderung mit Vorzeichen: „+0,80“ / „−237,33“.
    static func delta(_ v: Double?) -> String {
        guard let v else { return "–" }
        return v.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()).locale(de))
    }

    static func percent(_ v: Double?) -> String {
        guard let v else { return "–" }
        return v.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()).locale(de))
    }

    static func time(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(de))
    }
}

// MARK: - Farben (wie beim Server-Status-Widget)

enum Theme {
    static let bg = Color(hex: 0x111318)
    static let card = Color(hex: 0x1C2028)
    static let divider = Color(hex: 0x2A2F39)
    static let text = Color(hex: 0xE6E8EC)
    static let muted = Color(hex: 0x9AA1AD)
    static let green = Color(hex: 0x5BD18B)
    static let red = Color(hex: 0xF26D6D)

    static func trend(_ change: Double?) -> Color {
        guard let change else { return muted }
        return change >= 0 ? green : red
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
