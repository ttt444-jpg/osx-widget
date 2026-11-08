import Foundation
import WidgetKit

/// Gemeinsamer Speicher von Config-App und Widget-Extension (App Group).
///
/// Jedes Widget legt seine Einstellungen unter einem eigenen Schlüssel ab,
/// z. B. `stock.watchlist`. Die Config-App schreibt, die Widgets lesen.
enum SharedStore {
    /// Kommt aus der Info.plist (`AppGroupID`), damit die Team-ID nicht im Code steht.
    static var groupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
    }

    static var defaults: UserDefaults {
        groupID.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Speichert und lädt die Widgets der Art `kind` neu (oder alle, wenn `nil`).
    /// `reload: false` nur aus dem Widget selbst, damit es sich nicht erneut anstößt.
    static func save<T: Encodable>(_ value: T, key: String, reloading kind: String? = nil, reload: Bool = true) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
        guard reload else { return }
        if let kind {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        } else {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
