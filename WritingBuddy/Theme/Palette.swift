import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var label: String { self == .light ? "Light" : "Dark" }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

/// Color tokens mirroring `VIBES.native.{light,dark}` from the prototype.
struct Palette {
    // Surfaces
    let bg: Color
    let panel: Color
    let surfaceInset: Color
    let sidebar: Color
    let sidebarHover: Color
    let sidebarActive: Color
    let titlebarTop: Color
    let titlebarBottom: Color

    // Text
    let text: Color
    let muted: Color

    // Borders
    let border: Color
    let borderStrong: Color

    // Chip / accent
    let chip: Color
    let chipBorder: Color
    let chipActive: Color
    let chipActiveText: Color
    let accent: Color

    // Diff
    let diffAdd: Color
    let diffDel: Color
    let diffAddText: Color
    let diffDelText: Color

    // Modal
    let modalScrim: Color

    // Window shadow approximation
    let windowShadowColor: Color
    let windowShadowRadius: CGFloat
    let windowShadowY: CGFloat

    static func native(for theme: AppTheme) -> Palette {
        switch theme {
        case .light: return .lightNative
        case .dark:  return .darkNative
        }
    }

    static let lightNative = Palette(
        bg:             Color(hex: 0xF5F5F7),
        panel:          Color(hex: 0xFFFFFF),
        surfaceInset:   Color(hex: 0xFAFAFA),
        sidebar:        Color(hex: 0xEBEBEB),
        sidebarHover:   Color.black.opacity(0.05),
        sidebarActive:  Color(red: 0/255,  green: 122/255, blue: 255/255).opacity(0.12),
        titlebarTop:    Color(hex: 0xECECEC),
        titlebarBottom: Color(hex: 0xD8D8D8),

        text:           Color(hex: 0x1D1D1F),
        muted:          Color(hex: 0x86868B),

        border:         Color.black.opacity(0.10),
        borderStrong:   Color.black.opacity(0.18),

        chip:           Color(hex: 0xFFFFFF),
        chipBorder:     Color.black.opacity(0.12),
        chipActive:     Color(hex: 0x0A84FF),
        chipActiveText: Color.white,
        accent:         Color(hex: 0x0A84FF),

        diffAdd:        Color(red:  48/255, green: 209/255, blue: 88/255).opacity(0.22),
        diffDel:        Color(red: 255/255, green:  69/255, blue: 58/255).opacity(0.18),
        diffAddText:    Color(hex: 0x0A7A2F),
        diffDelText:    Color(hex: 0xA0241C),

        modalScrim:     Color.black.opacity(0.30),

        windowShadowColor: Color.black.opacity(0.28),
        windowShadowRadius: 30,
        windowShadowY: 22
    )

    static let darkNative = Palette(
        bg:             Color(hex: 0x1E1E1E),
        panel:          Color(hex: 0x2A2A2C),
        surfaceInset:   Color(hex: 0x222224),
        sidebar:        Color(hex: 0x252527),
        sidebarHover:   Color.white.opacity(0.05),
        sidebarActive:  Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.22),
        titlebarTop:    Color(hex: 0x3A3A3C),
        titlebarBottom: Color(hex: 0x2C2C2E),

        text:           Color(hex: 0xF5F5F7),
        muted:          Color(hex: 0x8E8E93),

        border:         Color.white.opacity(0.10),
        borderStrong:   Color.white.opacity(0.18),

        chip:           Color(hex: 0x3A3A3C),
        chipBorder:     Color.white.opacity(0.10),
        chipActive:     Color(hex: 0x0A84FF),
        chipActiveText: Color.white,
        accent:         Color(hex: 0x0A84FF),

        diffAdd:        Color(red:  48/255, green: 209/255, blue: 88/255).opacity(0.22),
        diffDel:        Color(red: 255/255, green:  69/255, blue: 58/255).opacity(0.20),
        diffAddText:    Color(hex: 0x7ADF8F),
        diffDelText:    Color(hex: 0xFF8B85),

        modalScrim:     Color.black.opacity(0.50),

        windowShadowColor: Color.black.opacity(0.50),
        windowShadowRadius: 30,
        windowShadowY: 22
    )

    var titlebarGradient: LinearGradient {
        LinearGradient(colors: [titlebarTop, titlebarBottom],
                       startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
