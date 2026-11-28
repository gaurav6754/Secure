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
    let orb1Hex: UInt32
    let orb2Hex: UInt32

    var bg: Color { Color(hex: bgHex) }
    var side: Color { Color(hex: sideHex) }
    var card: Color { Color(hex: cardHex) }
    var panel: Color { Color(hex: panelHex) }
    var line: Color { Color(hex: lineHex) }
    var fg: Color { Color(hex: fgHex) }
    var muted: Color { Color(hex: mutedHex) }
    var accent: Color { Color(hex: accentHex) }
    var orb1: Color { Color(hex: orb1Hex) }
    var orb2: Color { Color(hex: orb2Hex) }

    // Ported directly from PC ui_theme.py signature Glass & Wallpaper themes
    static let all: [AppThemePalette] = [
        .init(id: "aurora", name: "Aurora Glass", isLight: false, bgHex: 0x090B1A, sideHex: 0x0E1126, cardHex: 0x161B38, panelHex: 0x1F264C, lineHex: 0x333D70, fgHex: 0xF0F2FA, mutedHex: 0x95A0C6, accentHex: 0x8B7BFF, orb1Hex: 0x6D28D9, orb2Hex: 0x0EA5E9),
        .init(id: "ocean", name: "Ocean Glass", isLight: false, bgHex: 0x05101D, sideHex: 0x08182A, cardHex: 0x0F243C, panelHex: 0x163354, lineHex: 0x254D78, fgHex: 0xEAF6FF, mutedHex: 0x82AACB, accentHex: 0x22D3EE, orb1Hex: 0x0284C7, orb2Hex: 0x06B6D4),
        .init(id: "emerald", name: "Emerald Glass", isLight: false, bgHex: 0x05130E, sideHex: 0x091C15, cardHex: 0x102A20, panelHex: 0x183C2F, lineHex: 0x285A47, fgHex: 0xE8FBF3, mutedHex: 0x82B8A3, accentHex: 0x34D399, orb1Hex: 0x059669, orb2Hex: 0x10B981),
        .init(id: "sunset", name: "Sunset Glass", isLight: false, bgHex: 0x180912, sideHex: 0x220E1A, cardHex: 0x301626, panelHex: 0x422035, lineHex: 0x5D2F4B, fgHex: 0xFDF0F5, mutedHex: 0xC692AD, accentHex: 0xFB923C, orb1Hex: 0xDB2777, orb2Hex: 0xF97316),
        .init(id: "nebula", name: "Nebula Glass", isLight: false, bgHex: 0x090614, sideHex: 0x120B22, cardHex: 0x1C1334, panelHex: 0x281D48, lineHex: 0x3E2E6B, fgHex: 0xF3EEFF, mutedHex: 0xA696CE, accentHex: 0xC084FC, orb1Hex: 0x9333EA, orb2Hex: 0xEC4899),
        .init(id: "royal", name: "Royal Gold", isLight: false, bgHex: 0x0E0C18, sideHex: 0x161325, cardHex: 0x211D36, panelHex: 0x2E2949, lineHex: 0x463E68, fgHex: 0xFAF6E8, mutedHex: 0xB8AC92, accentHex: 0xF5C542, orb1Hex: 0xD97706, orb2Hex: 0x7C3AED),
        .init(id: "midnight", name: "Midnight", isLight: false, bgHex: 0x0E1018, sideHex: 0x12141F, cardHex: 0x1A1D2B, panelHex: 0x232739, lineHex: 0x2F354F, fgHex: 0xECEEF7, mutedHex: 0x8B91A8, accentHex: 0x8B7BFF, orb1Hex: 0x4F46E5, orb2Hex: 0x2563EB),
        .init(id: "oled", name: "OLED Black", isLight: false, bgHex: 0x000000, sideHex: 0x07070C, cardHex: 0x12121A, panelHex: 0x1D1D29, lineHex: 0x2E2E40, fgHex: 0xF4F4FA, mutedHex: 0x8D8DA3, accentHex: 0xA78BFA, orb1Hex: 0x5B21B6, orb2Hex: 0x1E1B4B),
        .init(id: "dracula", name: "Dracula", isLight: false, bgHex: 0x242632, sideHex: 0x1E2029, cardHex: 0x2D3040, panelHex: 0x383C50, lineHex: 0x4C526B, fgHex: 0xF8F8F2, mutedHex: 0xA2ABC9, accentHex: 0xBD93F9, orb1Hex: 0x7C3AED, orb2Hex: 0xEC4899),
        .init(id: "cloud", name: "Cloud Glass", isLight: true, bgHex: 0xE9EEF9, sideHex: 0xF5F7FC, cardHex: 0xFFFFFF, panelHex: 0xE2E7F5, lineHex: 0xCBD3E8, fgHex: 0x181C2B, mutedHex: 0x5A637D, accentHex: 0x6D5DFC, orb1Hex: 0x818CF8, orb2Hex: 0x38BDF8)
    ]
}

enum WallpaperStyle: String, CaseIterable, Identifiable {
    case auroraOrbs = "Aurora Glow"
    case meshWave = "Mesh Gradient"
    case solidMinimal = "Minimal Solid"

    var id: String { rawValue }
}

@MainActor
final class ThemeManager: ObservableObject {
    @Published var currentId: String {
        didSet { UserDefaults.standard.set(currentId, forKey: "secure_ai_theme_id") }
    }
    @Published var frostedGlass: Bool {
        didSet { UserDefaults.standard.set(frostedGlass, forKey: "secure_ai_frosted_glass") }
    }
    @Published var wallpaper: WallpaperStyle {
        didSet { UserDefaults.standard.set(wallpaper.rawValue, forKey: "secure_ai_wallpaper") }
    }
    @Published var customWallpaperKind: WallpaperKind {
        didSet { UserDefaults.standard.set(customWallpaperKind.rawValue, forKey: "secure_ai_custom_wp_kind") }
    }
    @Published var customWallpaperURL: String {
        didSet { UserDefaults.standard.set(customWallpaperURL, forKey: "secure_ai_custom_wp_url") }
    }
    @Published var customWallpaperFallbackURL: String {
        didSet { UserDefaults.standard.set(customWallpaperFallbackURL, forKey: "secure_ai_custom_wp_fallback_url") }
    }
    @Published var customWallpaperTitle: String {
        didSet { UserDefaults.standard.set(customWallpaperTitle, forKey: "secure_ai_custom_wp_title") }
    }
    @Published var wallpaperDimming: Double {
        didSet { UserDefaults.standard.set(wallpaperDimming, forKey: "secure_ai_wp_dimming") }
    }

    var palette: AppThemePalette {
        AppThemePalette.all.first(where: { $0.id == currentId }) ?? AppThemePalette.all[0]
    }

    init() {
        self.currentId = UserDefaults.standard.string(forKey: "secure_ai_theme_id") ?? "aurora"
        if UserDefaults.standard.object(forKey: "secure_ai_frosted_glass") == nil {
            self.frostedGlass = true
        } else {
            self.frostedGlass = UserDefaults.standard.bool(forKey: "secure_ai_frosted_glass")
        }
        let wpRaw = UserDefaults.standard.string(forKey: "secure_ai_wallpaper") ?? WallpaperStyle.auroraOrbs.rawValue
        self.wallpaper = WallpaperStyle(rawValue: wpRaw) ?? .auroraOrbs

        let kindRaw = UserDefaults.standard.string(forKey: "secure_ai_custom_wp_kind") ?? WallpaperKind.none.rawValue
        self.customWallpaperKind = WallpaperKind(rawValue: kindRaw) ?? .none
        self.customWallpaperURL = UserDefaults.standard.string(forKey: "secure_ai_custom_wp_url") ?? ""
        self.customWallpaperFallbackURL = UserDefaults.standard.string(forKey: "secure_ai_custom_wp_fallback_url") ?? ""
        self.customWallpaperTitle = UserDefaults.standard.string(forKey: "secure_ai_custom_wp_title") ?? ""
        if UserDefaults.standard.object(forKey: "secure_ai_wp_dimming") == nil {
            self.wallpaperDimming = 0.36
        } else {
            self.wallpaperDimming = UserDefaults.standard.double(forKey: "secure_ai_wp_dimming")
        }
    }

    func applyCustomWallpaper(_ item: WallpaperItem) {
        self.customWallpaperKind = item.kind
        self.customWallpaperURL = item.url
        self.customWallpaperFallbackURL = item.fallbackUrl ?? ""
        self.customWallpaperTitle = item.title
    }

    func clearCustomWallpaper() {
        self.customWallpaperKind = .none
        self.customWallpaperURL = ""
        self.customWallpaperFallbackURL = ""
        self.customWallpaperTitle = ""
    }
}

/// 120Hz ProMotion GPU-accelerated Frosted Glass + Static/Live MP4 Wallpaper backdrop for the SECURE AI sidebar
struct FrostedWallpaperBackdrop: View {
    let palette: AppThemePalette
    let style: WallpaperStyle
    let frosted: Bool
    var customKind: WallpaperKind = .none
    var customURL: String = ""
    var customFallbackURL: String = ""
    var dimming: Double = 0.36
    var isActive: Bool = true

    var body: some View {
        ZStack {
            palette.side

            if customKind == .live && !customURL.isEmpty {
                LiveWallpaperPlayerView(
                    urlString: customURL,
                    fallbackUrlString: customFallbackURL,
                    isActive: isActive
                )
                .clipped()
                Color.black.opacity(min(max(dimming, 0.05), 0.80))
            } else if customKind == .static && !customURL.isEmpty {
                StaticWallpaperImageView(urlString: customURL, isThumbnail: false)
                    .clipped()
                Color.black.opacity(min(max(dimming, 0.05), 0.80))
            } else if style == .auroraOrbs {
                GeometryReader { geo in
                    Circle()
                        .fill(palette.orb1.opacity(palette.isLight ? 0.25 : 0.36))
                        .frame(width: geo.size.width * 1.1, height: geo.size.width * 1.1)
                        .blur(radius: 75)
                        .offset(x: -geo.size.width * 0.3, y: -60)

                    Circle()
                        .fill(palette.orb2.opacity(palette.isLight ? 0.22 : 0.30))
                        .frame(width: geo.size.width * 0.95, height: geo.size.width * 0.95)
                        .blur(radius: 70)
                        .offset(x: geo.size.width * 0.28, y: geo.size.height * 0.55)
                }
            } else if style == .meshWave {
                LinearGradient(
                    colors: [palette.orb1.opacity(0.28), palette.side, palette.orb2.opacity(0.24)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            if frosted {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(customKind == .none ? (palette.isLight ? 0.55 : 0.42) : (palette.isLight ? 0.38 : 0.28))
            }
        }
        .clipped()
        .ignoresSafeArea()
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
