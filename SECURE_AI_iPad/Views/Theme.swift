import SwiftUI

struct AppThemePalette: Identifiable, Hashable {
    let id: String
    let name: String
    let isLight: Bool
    let bgHex: UInt32
    let sideHex: UInt32
    let cardHex: UInt32
    let panelHex: UInt32
    let lineHex: UInt32
    let fgHex: UInt32
    let mutedHex: UInt32
    let accentHex: UInt32

    var bg: Color { Color(hex: bgHex) }
    var side: Color { Color(hex: sideHex) }
    var card: Color { Color(hex: cardHex) }
    var panel: Color { Color(hex: panelHex) }
    var line: Color { Color(hex: lineHex) }
    var fg: Color { Color(hex: fgHex) }
    var muted: Color { Color(hex: mutedHex) }
    var accent: Color { Color(hex: accentHex) }

    // Ported directly from PC ui_theme.py signature themes
    static let all: [AppThemePalette] = [
        .init(id: "aurora", name: "Aurora Glass", isLight: false, bgHex: 0x0B0D1F, sideHex: 0x10132A, cardHex: 0x171B36, panelHex: 0x202546, lineHex: 0x2E355E, fgHex: 0xECEEF7, mutedHex: 0x8F97B8, accentHex: 0x8B7BFF),
        .init(id: "midnight", name: "Midnight", isLight: false, bgHex: 0x0E1018, sideHex: 0x12141F, cardHex: 0x1A1D2B, panelHex: 0x232739, lineHex: 0x2B3047, fgHex: 0xECEEF7, mutedHex: 0x8B91A8, accentHex: 0x8B7BFF),
        .init(id: "ocean", name: "Ocean Glass", isLight: false, bgHex: 0x06121F, sideHex: 0x091A2C, cardHex: 0x10253C, panelHex: 0x17324F, lineHex: 0x22466B, fgHex: 0xEAF6FF, mutedHex: 0x7EA4C4, accentHex: 0x22D3EE),
        .init(id: "emerald", name: "Emerald Glass", isLight: false, bgHex: 0x06140F, sideHex: 0x0A1D16, cardHex: 0x112B21, panelHex: 0x193B2E, lineHex: 0x265241, fgHex: 0xE8FBF3, mutedHex: 0x7EB39E, accentHex: 0x34D399),
        .init(id: "sunset", name: "Sunset Glass", isLight: false, bgHex: 0x1A0B14, sideHex: 0x24101C, cardHex: 0x311727, panelHex: 0x402033, lineHex: 0x572D46, fgHex: 0xFDF0F5, mutedHex: 0xC18EA8, accentHex: 0xFB923C),
        .init(id: "nebula", name: "Nebula Glass", isLight: false, bgHex: 0x0A0714, sideHex: 0x120C22, cardHex: 0x1C1433, panelHex: 0x271D46, lineHex: 0x3A2C63, fgHex: 0xF3EEFF, mutedHex: 0xA292C9, accentHex: 0xC084FC),
        .init(id: "royal", name: "Royal Gold", isLight: false, bgHex: 0x0F0D1A, sideHex: 0x171426, cardHex: 0x221E36, panelHex: 0x2E2947, lineHex: 0x423B61, fgHex: 0xFAF6E8, mutedHex: 0xB3A88E, accentHex: 0xF5C542),
        .init(id: "oled", name: "OLED Black", isLight: false, bgHex: 0x000000, sideHex: 0x08080D, cardHex: 0x12121A, panelHex: 0x1C1C27, lineHex: 0x2A2A38, fgHex: 0xF4F4FA, mutedHex: 0x8A8A9E, accentHex: 0xA78BFA),
        .init(id: "dracula", name: "Dracula", isLight: false, bgHex: 0x282A36, sideHex: 0x21222C, cardHex: 0x303341, panelHex: 0x3A3E50, lineHex: 0x4B5066, fgHex: 0xF8F8F2, mutedHex: 0x9FA8C7, accentHex: 0xBD93F9),
        .init(id: "cloud", name: "Cloud Light", isLight: true, bgHex: 0xEEF1F8, sideHex: 0xF7F8FC, cardHex: 0xFFFFFF, panelHex: 0xE4E8F3, lineHex: 0xCFD6E8, fgHex: 0x1B1F2E, mutedHex: 0x5E6680, accentHex: 0x6D5DFC)
    ]
}

@MainActor
final class ThemeManager: ObservableObject {
    @Published var currentId: String {
        didSet { UserDefaults.standard.set(currentId, forKey: "secure_ai_theme_id") }
    }

    var palette: AppThemePalette {
        AppThemePalette.all.first(where: { $0.id == currentId }) ?? AppThemePalette.all[0]
    }

    init() {
        self.currentId = UserDefaults.standard.string(forKey: "secure_ai_theme_id") ?? "aurora"
    }
}

enum SecureTheme {
    static let bg      = Color(hex: 0x0E1018)
    static let side    = Color(hex: 0x12141F)
    static let card    = Color(hex: 0x1A1D2B)
    static let panel   = Color(hex: 0x232739)
    static let line    = Color(hex: 0x2B3047)
    static let fg      = Color(hex: 0xECEEF7)
    static let muted   = Color(hex: 0x8B91A8)
    static let accent  = Color(hex: 0x8B7BFF)
    static let blue    = Color(hex: 0x3B82F6)
    static let violet  = Color(hex: 0x7C3AED)
    static let green   = Color(hex: 0x22C55E)
    static let red     = Color(hex: 0xEF4444)
    static let amber   = Color(hex: 0xF5A524)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
