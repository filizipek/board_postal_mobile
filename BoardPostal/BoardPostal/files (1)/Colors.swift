import SwiftUI

// MARK: - board_postal Design System — Colors
// Mediterranean blue palette. Sharp corners throughout.

extension Color {
    // Primary palette
    static let bpCobalt    = Color(hex: "#1B4FDB") // Primary blue, main CTA
    static let bpInk       = Color(hex: "#0D1B2A") // Near-black, deep navy
    static let bpAzure     = Color(hex: "#5B9BF5") // Light blue, italic highlights
    static let bpSaffron   = Color(hex: "#E8A020") // Accent gold, editor badges
    static let bpLimestone = Color(hex: "#F0F2F5") // Cool off-white background
    static let bpStone     = Color(hex: "#D4DAE8") // Borders, dividers
    static let bpPrimaryDeep = Color(hex: "#0F1E3A") // Dark hero backgrounds

    // Semantic aliases
    static let bpBackground = Color(hex: "#F0F2F5")
    static let bpSurface    = Color.white
    static let bpBorder     = Color(hex: "#D4DAE8")
    static let bpTextPrimary    = Color(hex: "#0D1B2A")
    static let bpTextSecondary  = Color(hex: "#4A5568")
    static let bpTextMuted      = Color(hex: "#718096")

    // Status
    static let bpSuccess = Color(hex: "#2D7D46")
    static let bpError   = Color(hex: "#C53030")
    static let bpWarning = Color(hex: "#D97706")
}

// MARK: - Hex initializer
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - UIColor bridge (for UIKit components)
extension UIColor {
    static let bpCobalt     = UIColor(Color.bpCobalt)
    static let bpInk        = UIColor(Color.bpInk)
    static let bpSaffron    = UIColor(Color.bpSaffron)
    static let bpLimestone  = UIColor(Color.bpLimestone)
    static let bpBackground = UIColor(Color.bpBackground)
}

// MARK: - Cover gradient fallbacks
// Used when a trip has no cover photo. Each gradient is paired
// deterministically to a trip id via stable hash.
extension LinearGradient {
    static let bpCoverGradients: [LinearGradient] = [
        LinearGradient(colors: [
            Color(hex: "#0F2D5A"), Color(hex: "#0A1628")],
            startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [
            Color(hex: "#1A1A2E"), Color(hex: "#16213E")],
            startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [
            Color(hex: "#0D2137"), Color(hex: "#1B4FDB").opacity(0.4)],
            startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [
            Color(hex: "#1B3A6B"), Color(hex: "#0A1628")],
            startPoint: .topTrailing, endPoint: .bottomLeading),
        LinearGradient(colors: [
            Color(hex: "#2C1810"), Color(hex: "#E8A020").opacity(0.3)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
    ]

    static func bpCoverGradient(for id: String) -> LinearGradient {
        let hash = id.utf8.reduce(0) { $0 &+ Int($1) }
        return bpCoverGradients[abs(hash) % bpCoverGradients.count]
    }
}
