import SwiftUI

/// Gemeinsame Farben aller Widgets (dunkles Design).
enum Theme {
    static let bg = Color(hex: 0x111318)
    static let card = Color(hex: 0x1C2028)
    static let divider = Color(hex: 0x2A2F39)
    static let text = Color(hex: 0xE6E8EC)
    static let muted = Color(hex: 0x9AA1AD)
    static let green = Color(hex: 0x5BD18B)
    static let yellow = Color(hex: 0xF2B84B)
    static let red = Color(hex: 0xF26D6D)
    static let blue = Color(hex: 0x6EA8FE)

    /// Grün bei Plus, Rot bei Minus, Grau ohne Wert oder ohne Veränderung.
    static func trend(_ change: Double?) -> Color {
        guard let change, abs(change) >= 0.00005 else { return muted }
        return change > 0 ? green : red
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
