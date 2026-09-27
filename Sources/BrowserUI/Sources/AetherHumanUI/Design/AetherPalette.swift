import AppKit
import SwiftUI

// Warm neutral family (stone), not cold grey. Every surface in both schemes
// comes from this one ramp so light and dark feel like the same product.
public enum AetherNeutral {
    // Dark scheme: warm charcoal, never pure black.
    public static let background: UInt = 0x151413
    public static let chrome: UInt = 0x1F1E1C
    public static let card: UInt = 0x232120
    public static let hover: UInt = 0x2C2A27
    public static let selected: UInt = 0x35322E
    public static let input: UInt = 0x2A2825
    public static let focus: UInt = 0x3A3733
    public static let dropdownNested: UInt = 0x272523
    public static let text: UInt = 0xF5F5F4
    public static let textStrong: UInt = 0xFAFAF9
    public static let muted: UInt = 0xA8A29E
    public static let tertiary: UInt = 0x78716C
    public static let hairline: UInt = 0xFFFFFF
    public static let focusRing: UInt = 0x57534E
    public static let folderBlue: UInt = 0x2563EB
    public static let closeOnLight: UInt = 0x1A1B1F

    // Light scheme: warm off-white (porcelain), never pure white.
    public static let lightBackground: UInt = 0xFBFAF8
    public static let lightChrome: UInt = 0xF6F4EF
    public static let lightCard: UInt = 0xF5F4F1
    public static let lightHover: UInt = 0xE9E6E0
    public static let lightSelected: UInt = 0xE2DED7
    public static let lightText: UInt = 0x1C1917
    public static let lightTextStrong: UInt = 0x0C0A09
    public static let lightMuted: UInt = 0x57534E
    public static let lightTertiary: UInt = 0x78716C
    public static let lightHairline: UInt = 0x000000
}

public enum AetherPalette {
    private static func color(_ hex: UInt, alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255, opacity: alpha)
    }

    private static func neutral(_ dark: Bool, darkHex: UInt, lightHex: UInt, alpha: Double = 1) -> Color {
        color(dark ? darkHex : lightHex, alpha: alpha)
    }

    public static func background(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.background, lightHex: AetherNeutral.lightBackground)
    }
    public static func chrome(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.chrome, lightHex: AetherNeutral.lightChrome)
    }
    public static func card(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func hover(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
    }
    public static func selected(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.12) : Color.black.opacity(0.07)
    }
    /// Sidebar selection: the exact fill under every rendering sidebar row.
    /// Search/dropdown selected rows reuse this verbatim so text contrast
    /// matches the sidebar instead of inventing its own highlight.
    public static func sidebarSelection(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
    public static func text(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.text, lightHex: AetherNeutral.lightText)
    }
    public static func textStrong(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textStrong, lightHex: AetherNeutral.lightTextStrong)
    }
    public static func muted(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.muted, lightHex: AetherNeutral.lightMuted)
    }
    /// One hairline for every card edge and separator. Visible but quiet:
    /// an invisible hairline is why cards used to read as borderless slabs.
    public static func hairline(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }
    public static func input(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.input, lightHex: AetherNeutral.lightHover)
    }
    public static func tertiary(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.tertiary, lightHex: AetherNeutral.lightTertiary)
    }
    public static func dropdownNested(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.dropdownNested, lightHex: AetherNeutral.lightHover)
    }
    public static func panel(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func control(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func raised(_ dark: Bool) -> Color {
        // The raised control step and the selection step are the same elevation:
        // one definition, so a selected control can never disagree with a
        // selected row.
        selected(dark)
    }
    public static func ink(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.text, lightHex: AetherNeutral.lightText)
    }
    public static func heading(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textStrong, lightHex: AetherNeutral.lightTextStrong)
    }
    public static func soft(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.muted, lightHex: AetherNeutral.lightMuted)
    }
    public static func placeholder(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.muted, lightHex: AetherNeutral.lightMuted)
    }
    public static func suggestionSelected(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.selected, lightHex: AetherNeutral.lightSelected)
    }
    public static func omnibox(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func composer(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func settingsCanvas(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.background, lightHex: AetherNeutral.lightBackground)
    }
    public static func settingsCard(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func inputFocus(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.selected, lightHex: AetherNeutral.lightSelected)
    }
    public static func tabActive(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.background, lightHex: AetherNeutral.lightBackground)
    }
    public static func tabTitle(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.muted, lightHex: AetherNeutral.lightMuted)
    }
    public static func selection(_ dark: Bool) -> Color {
        selected(dark)
    }
    public static func tabHover(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.hover, lightHex: AetherNeutral.lightHover)
    }
    public static func modal(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func dialogCard(_ dark: Bool) -> Color {
        card(dark)
    }
    public static func dialogField(_ dark: Bool) -> Color {
        input(dark)
    }
    public static func focusRing(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.focusRing, lightHex: 0x4A4E57)
    }
    public static func error(_ dark: Bool) -> Color {
        color(dark ? 0xE5A0A0 : 0x8A1F1F)
    }
    public static func errorBackground(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func active(_ dark: Bool) -> Color {
        color(dark ? 0x7FB98C : 0x2F6B3C)
    }
    public static func focus(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.focus, lightHex: AetherNeutral.lightSelected)
    }
    public static func glowCore(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textStrong, lightHex: AetherNeutral.lightTextStrong)
    }
    public static func glowMid(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.muted, lightHex: AetherNeutral.lightMuted)
    }
    public static func glowOuter(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.selected, lightHex: AetherNeutral.lightSelected)
    }
    public static func chromeHover(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.hover, lightHex: AetherNeutral.lightHover)
    }
    public static func panelBottom(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func settingsRaised(_ dark: Bool) -> Color {
        dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
    public static func inset(_ dark: Bool) -> Color {
        input(dark)
    }
    public static func navigation(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.muted, lightHex: AetherNeutral.lightMuted)
    }
    public static func canvas(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.background, lightHex: AetherNeutral.lightBackground)
    }
    public static func pinTop(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func pinBottom(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func profileTop(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.selected, lightHex: AetherNeutral.lightSelected)
    }
    public static func profileBottom(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.selected, lightHex: AetherNeutral.lightSelected)
    }
    public static let folderColor = color(AetherNeutral.folderBlue)
    public static func siteSurface(_ hex: UInt) -> Color { color(hex) }
    public static func siteInk(_ hex: UInt) -> Color {
        let r = Double((hex >> 16) & 255) / 255
        let g = Double((hex >> 8) & 255) / 255
        let b = Double(hex & 255) / 255
        return r * 0.2126 + g * 0.7152 + b * 0.0722 > 0.50 ? .black : .white
    }
    public static func activeSite(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.background, lightHex: AetherNeutral.lightBackground)
    }
    public static func activeNewTab(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.background, lightHex: AetherNeutral.lightBackground)
    }
    public static func subtle(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func surface(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.background, lightHex: AetherNeutral.lightBackground)
    }
}

/// One shape scale. Every surface picks a step from this list — nothing invents
/// its own rounding: 8 inline controls, 10 fields, 12 cards, 14 large panels.
public enum AetherMetrics {
    /// Smallest step: rows, chips, inline buttons, tiles, tab-strip buttons.
    public static let utilityRadius: CGFloat = 8
    /// Every text input and search well.
    public static let fieldRadius: CGFloat = 10
    /// Every floating card: popover, menu, suggestion list, dropdown, popup panel.
    public static let cardRadius: CGFloat = 12
    /// Full-window panels: history, bookmarks, reader, inspector, settings.
    public static let panelRadius: CGFloat = 14
    /// Top-tab shape only.
    public static let tabRadius: CGFloat = 14
    public static let tabHeight: CGFloat = 40
    public static let rowHeight: CGFloat = 33
    public static let chromeHeight: CGFloat = 42
    public static let navigationHeight: CGFloat = 40
    public static let iconCanvas: CGFloat = 20
    public static let tapTarget: CGFloat = 44
    public static let sidebarWidth: CGFloat = 190
    public static let minSidebarWidth: CGFloat = 160
    public static let maxSidebarWidth: CGFloat = 320
    public static let settingsSidebar: CGFloat = 218
    public static let tabWidth: CGFloat = 174
    public static let tabMinWidth: CGFloat = 108
    public static let tabMaxWidth: CGFloat = 207
    public static let tabShoulder: CGFloat = 12
    public static let profileClusterWidth: CGFloat = 200
    public static let profileClusterHeight: CGFloat = 32
}

// Accent applies only to explicit theme affordances, not neutral browser-owned surfaces.
public enum AetherProgressColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case violet = "Violet"
    case indigo = "Indigo"
    case blue = "Blue"
    case teal = "Teal"
    case green = "Green"
    case yellow = "Yellow"
    case orange = "Orange"
    case rose = "Rose"
    case neutral = "Neutral"
    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .violet: Color(red: 0.55, green: 0.36, blue: 0.96)
        case .indigo: Color(red: 0.39, green: 0.40, blue: 0.95)
        case .blue: Color(red: 0.23, green: 0.51, blue: 0.96)
        case .teal: Color(red: 0.08, green: 0.72, blue: 0.65)
        case .green: Color(red: 0.13, green: 0.77, blue: 0.37)
        case .yellow: Color(red: 0.92, green: 0.70, blue: 0.03)
        case .orange: Color(red: 0.98, green: 0.45, blue: 0.09)
        case .rose: Color(red: 0.96, green: 0.25, blue: 0.37)
        case .neutral: Color(red: 0.83, green: 0.83, blue: 0.83)
        }
    }

    public var gradientTrio: (UInt, UInt, UInt) {
        switch self {
        case .violet: (0x6D28D9, 0xA78BFA, 0xEDE9FE)
        case .indigo: (0x4338CA, 0x818CF8, 0xE0E7FF)
        case .blue: (0x1D4ED8, 0x60A5FA, 0xDBEAFE)
        case .teal: (0x0F766E, 0x2DD4BF, 0xCCFBF1)
        case .green: (0x15803D, 0x4ADE80, 0xDCFCE7)
        case .yellow: (0xA16207, 0xFDE047, 0xFEF9C3)
        case .orange: (0xC2410C, 0xFB923C, 0xFFEDD5)
        case .rose: (0xBE123C, 0xFB7185, 0xFFE4E6)
        case .neutral: (0xA3A3A3, 0xE5E5E5, 0xFFFFFF)
        }
    }
}

/// One elevation ramp for every floating surface. Native popovers carry real
/// depth; near-zero alphas are why cards used to read as flat slabs that were
/// pasted onto the page instead of floating above it.
public enum AetherShadow {
    public static func minimal(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.22 : 0.06), 4, 1)
    }
    public static func resting(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.34 : 0.11), 12, 3)
    }
    public static func floating(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.44 : 0.15), 18, 6)
    }
    public static func sheet(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.54 : 0.20), 30, 12)
    }
}
