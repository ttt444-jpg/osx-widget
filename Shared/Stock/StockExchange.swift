import Foundation

/// Ermittelt die Börse, an der ein Wert hauptsächlich gehandelt wird (zweite Zeile im Widget).
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
        struct Listing: Decodable { let exchCode: String? }
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

    /// ISIN → Börse für mehrere Werte (OpenFIGI erlaubt 10 pro Anfrage ohne Key).
    static func lookup(_ isins: [String]) async -> [String: String] {
        var result: [String: String] = [:]
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
                let codes = Set((response.data ?? []).compactMap(\.exchCode))
                if let name = name(isin: isin, codes: codes) { result[isin] = name }
            }
        }
        return result
    }
}
