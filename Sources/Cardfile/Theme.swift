import SwiftUI

enum Theme {
    static let space: CGFloat = 8

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#161311") : Color(hex: "#F3EDE4")
    }

    static func sidebar(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#1E1A17") : Color(hex: "#E7DFD4")
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#26211D") : Color(hex: "#FFFCF8")
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#F6F1EA") : Color(hex: "#1F1A16")
    }

    static func secondary(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#C4B8AC") : Color(hex: "#4E463F")
    }

    static func line(_ scheme: ColorScheme, increased: Bool) -> Color {
        if increased { return scheme == .dark ? Color(hex: "#F6F1EA") : Color(hex: "#1F1A16") }
        return scheme == .dark ? Color(hex: "#3A332C") : Color(hex: "#DDD3C7")
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#8FCBAA") : Color(hex: "#1B5E3B")
    }

    static func onAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#10281C") : Color(hex: "#FFFCF8")
    }

    static func accentSoft(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#1E3A2C") : Color(hex: "#E4F2EA")
    }

    static func danger(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#F0B4A8") : Color(hex: "#8C2F22")
    }

    static func paperRule(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#3A332C") : Color(hex: "#E4D9CC")
    }

    static func wash(_ seed: String, _ scheme: ColorScheme) -> Color {
        let palette = scheme == .dark
            ? ["#3A2A24", "#24352C", "#2A3140", "#3A3324", "#32283A", "#24383A"]
            : ["#E8D5C8", "#D7E4D6", "#D9DEE8", "#E8E0C8", "#E4D6E0", "#D4E3E4"]
        var hash = 0
        for scalar in seed.unicodeScalars { hash = hash &* 31 &+ Int(scalar.value) }
        let hex = palette[abs(hash) % palette.count]
        return Color(hex: hex)
    }

    enum Radius {
        static let chip: CGFloat = 4
        static let card: CGFloat = 12
        static let bar: CGFloat = 14
        static let panel: CGFloat = 18
    }
}

extension Color {
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
