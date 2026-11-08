import Foundation
import SwiftUI

// MARK: - Datenmodell (entspricht dem JSON von status_api.py)

struct ServerStatus: Codable {
    struct Count: Codable {
        let up: Int
        let total: Int
        var ok: Bool { up >= total }
        var text: String { "\(up)/\(total)" }
    }

    struct Patches: Codable {
        let updates: Int?
        let security: Int?
        let rebootRequired: Bool?
        let lastAutoUpdateHours: Double?
    }

    struct Scrape: Codable {
        let ok: Bool?
        let sourcesOk: Int?
        let sourcesTotal: Int?
        let lastRunHours: Double?
    }

    struct Resources: Codable {
        let cpu: Double?
        let ram: Double?
        let swap: Double?
        let disk: Double?
        let load5: Double?
        let uptimeDays: Double?
    }

    struct History: Codable {
        let cpu: [Double]
        let ram: [Double]
    }

    let generatedAt: Double
    let overall: String
    let problems: [String]
    let websites: Count?
    let services: Count?
    let containers: Count?
    let alerts: Int?
    let patches: Patches?
    let certMinDays: Int?
    let lynis: Int?
    let fail2banBanned: Int?
    let scrape: Scrape?
    let resources: Resources?
    let history: History?

    var health: Health { Health(rawValue: overall) ?? .unknown }
    var generatedDate: Date { Date(timeIntervalSince1970: generatedAt) }
}

enum Health: String {
    case ok, warn, crit, unknown

    var color: Color {
        switch self {
        case .ok: return Theme.green
        case .warn: return Theme.yellow
        case .crit: return Theme.red
        case .unknown: return Theme.muted
        }
    }

    var title: String {
        switch self {
        case .ok: return "Alles in Ordnung"
        case .warn: return "Hinweise"
        case .crit: return "Störung"
        case .unknown: return "Keine Daten"
        }
    }
}

// MARK: - Laden

enum StatusFetcher {
    enum FetchError: LocalizedError {
        case badURL, unauthorized, http(Int)
        var errorDescription: String? {
            switch self {
            case .badURL: return "Ungültige URL"
            case .unauthorized: return "Token falsch"
            case .http(let code): return "HTTP \(code)"
            }
        }
    }

    static func fetch(url: String, token: String) async throws -> ServerStatus {
        guard let u = URL(string: url.trimmingCharacters(in: .whitespaces)), u.scheme != nil else {
            throw FetchError.badURL
        }
        var request = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw FetchError.unauthorized }
        guard code == 200 else { throw FetchError.http(code) }
        return try JSONDecoder().decode(ServerStatus.self, from: data)
    }

    static let sample = ServerStatus(
        generatedAt: Date().timeIntervalSince1970,
        overall: "ok",
        problems: [],
        websites: .init(up: 9, total: 9),
        services: .init(up: 14, total: 14),
        containers: .init(up: 8, total: 8),
        alerts: 0,
        patches: .init(updates: 0, security: 0, rebootRequired: false, lastAutoUpdateHours: 10),
        certMinDays: 63,
        lynis: 81,
        fail2banBanned: 17,
        scrape: .init(ok: true, sourcesOk: 22, sourcesTotal: 22, lastRunHours: 3),
        resources: .init(cpu: 16, ram: 50, swap: 5, disk: 48, load5: 0.43, uptimeDays: 1),
        history: .init(
            cpu: (0..<48).map { 15 + 8 * sin(Double($0) / 4) + Double($0 % 5) },
            ram: (0..<48).map { 48 + 3 * sin(Double($0) / 7) }
        )
    )
}

// MARK: - Farben (wie im Mockup)

enum Theme {
    static let bg = Color(hex: 0x111318)
    static let card = Color(hex: 0x1C2028)
    static let track = Color(hex: 0x2A2F39)
    static let text = Color(hex: 0xE6E8EC)
    static let muted = Color(hex: 0x9AA1AD)
    static let green = Color(hex: 0x5BD18B)
    static let yellow = Color(hex: 0xF2B84B)
    static let red = Color(hex: 0xF26D6D)
    static let blue = Color(hex: 0x6EA8FE)
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
