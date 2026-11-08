import Foundation

/// Ermittelt Börse und (bei ETFs) Anbieter für die zweite Zeile im Widget, z. B. „iShares · Xetra“.
///
/// Quelle: OpenFIGI (Bloomberg), kostenlos und ohne Key. Liefert zu einer ISIN die
/// Kürzel aller Handelsplätze; daraus wird die Heimatbörse abgeleitet:
/// NVIDIA hat `UW` → NASDAQ, JPMorgan nur `UN` → NYSE, Cresco `CF` → CSE,
/// iShares-ETFs `GR` (Deutschland) → Xetra.
enum StockExchange {
    private static let url = URL(string: "https://api.openfigi.com/v3/mapping")!

    private struct Job: Encodable {
        let idType = "ID_ISIN"
        let idValue: String
    }

    private struct Response: Decodable {
        struct Listing: Decodable {
            let exchCode: String?
            let name: String?
        }
        let data: [Listing]?
    }

    private static let us = [("UW", "NASDAQ"), ("UQ", "NASDAQ"), ("UR", "NASDAQ"),
                             ("UN", "NYSE"), ("UA", "NYSE American"), ("UP", "NYSE Arca")]
    private static let ca = [("CT", "TSX"), ("CV", "TSX Venture"), ("CF", "CSE")]
    private static let eu = [("GY", "Xetra"), ("GR", "Xetra"), ("LN", "London"),
                             ("NA", "Euronext Amsterdam"), ("FP", "Euronext Paris"),
                             ("SW", "SIX"), ("IM", "Borsa Italiana"), ("AV", "Wien")]

    /// Heimatbörse aus den Börsenkürzeln; die Reihenfolge hängt vom Land der ISIN ab.
    static func name(isin: String, codes: Set<String>) -> String? {
        let order: [(String, String)]
        switch isin.prefix(2) {
        case "US": order = us + ca + eu
        case "CA": order = ca + us + eu
        default: order = eu + us + ca
        }
        return order.first { codes.contains($0.0) }?.1
    }

    struct Info {
        let exchange: String?
        /// Alle Namen des Werts bei OpenFIGI, z. B. „ISHARES CORE MSCI WORLD“.
        let names: [String]
    }

    /// ISIN → Börse und Namen für mehrere Werte (OpenFIGI erlaubt 10 pro Anfrage ohne Key).
    static func lookup(_ isins: [String]) async -> [String: Info] {
        var result: [String: Info] = [:]
        for start in stride(from: 0, to: isins.count, by: 10) {
            let batch = Array(isins[start..<min(start + 10, isins.count)])
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(batch.map { Job(idValue: $0) })
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let responses = try? JSONDecoder().decode([Response].self, from: data)
            else { continue }
            for (isin, response) in zip(batch, responses) {
                let listings = response.data ?? []
                guard !listings.isEmpty else { continue }
                let codes = Set(listings.compactMap(\.exchCode))
                result[isin] = Info(exchange: name(isin: isin, codes: codes),
                                    names: Array(Set(listings.compactMap(\.name))))
            }
        }
        return result
    }

    // MARK: - Anbieter (nur ETFs)

    /// Namensanfänge → Anbieter. Geprüft wird in Großbuchstaben, längere Muster zuerst.
    private static let providers: [(String, String)] = [
        ("ISHARES", "iShares"), ("ISHS", "iShares"), ("ISH ", "iShares"), ("ISHSII", "iShares"),
        ("VANGUARD", "Vanguard"), ("VANG", "Vanguard"),
        ("XTRACKERS", "Xtrackers"), ("DB X-TRACKERS", "Xtrackers"), ("XTR", "Xtrackers"),
        ("X(", "Xtrackers"), ("X ", "Xtrackers"),
        ("SPDR", "SPDR"), ("SS SPDR", "SPDR"),
        ("AMUNDI", "Amundi"), ("LYXOR", "Amundi"), ("AM.", "Amundi"), ("MUL AMUN", "Amundi"),
        ("INVESCO", "Invesco"), ("UBS", "UBS"), ("WISDOMTREE", "WisdomTree"), ("VANECK", "VanEck"),
        ("HSBC", "HSBC"), ("L&G", "L&G"), ("LEGAL & GENERAL", "L&G"), ("FRANKLIN", "Franklin"),
        ("JPM", "J.P. Morgan"), ("JPMORGAN", "J.P. Morgan"), ("GLOBAL X", "Global X"),
        ("FIDELITY", "Fidelity"), ("DWS", "DWS"), ("DEKA", "Deka"), ("COMSTAGE", "Amundi"),
    ]

    /// Anbieter aus einem der Namen, z. B. „iShares Core MSCI World“ → „iShares“.
    static func provider(from names: [String]) -> String? {
        let sorted = providers.sorted { $0.0.count > $1.0.count }
        for name in names {
            let upper = name.uppercased()
            if let hit = sorted.first(where: { upper.hasPrefix($0.0) }) { return hit.1 }
        }
        return nil
    }
}
