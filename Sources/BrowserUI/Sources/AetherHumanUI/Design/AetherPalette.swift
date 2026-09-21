import AppKit
import SwiftUI

public enum AetherNeutral {
    public static let background: UInt = 0x171717
    public static let chrome: UInt = 0x1B1B1B
    public static let card: UInt = 0x202020
    public static let hover: UInt = 0x292929
    public static let selected: UInt = 0x2D2D2D
    public static let text: UInt = 0xF5F5F5
    public static let textStrong: UInt = 0xFAFAFA
    public static let muted: UInt = 0xA3A3A3
    public static let hairline: UInt = 0xFFFFFF

    public static let lightBackground: UInt = 0xFFFFFF
    public static let lightChrome: UInt = 0xF7F7F7
    public static let lightCard: UInt = 0xF5F5F5
    public static let lightHover: UInt = 0xE8E8E8
    public static let lightSelected: UInt = 0xE0E0E0
    public static let lightText: UInt = 0x171717
    public static let lightTextStrong: UInt = 0x000000
    public static let lightMuted: UInt = 0x525252
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
        neutral(dark, darkHex: AetherNeutral.hover, lightHex: AetherNeutral.lightHover)
    }
    public static func selected(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.selected, lightHex: AetherNeutral.lightSelected)
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
    public static func hairline(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.hairline, lightHex: AetherNeutral.lightHairline, alpha: 0.07)
    }
    public static func panel(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func control(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
    }
    public static func raised(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.selected, lightHex: AetherNeutral.lightSelected)
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
        neutral(dark, darkHex: AetherNeutral.selected, lightHex: AetherNeutral.lightSelected)
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
        neutral(dark, darkHex: AetherNeutral.selected, lightHex: AetherNeutral.lightSelected)
    }
    public static func inset(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.card, lightHex: AetherNeutral.lightCard)
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

public enum AetherMetrics {
    public static let cardRadius: CGFloat = 8
    public static let fieldRadius: CGFloat = 6
    public static let utilityRadius: CGFloat = 5
    public static let menuRadius: CGFloat = 10
    public static let panelRadius: CGFloat = 8
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
    public static let profileClusterWidth: CGFloat = 322
    public static let profileClusterHeight: CGFloat = 32
}

// Accent applies only to explicit theme affordances, not neutral browser-owned surfaces.
public enum AetherProgressColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case violet = "Violet"
    case orange = "Orange"
    case green = "Green"
    case neutral = "Neutral"
    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .violet: Color(red: 0.58, green: 0.43, blue: 0.98)
        case .orange: Color(red: 0.98, green: 0.55, blue: 0.26)
        case .green: Color(red: 0.34, green: 0.80, blue: 0.53)
        case .neutral: Color(red: 0.85, green: 0.85, blue: 0.85)
        }
    }

    public var gradientTrio: (UInt, UInt, UInt) {
        switch self {
        case .violet: (0x5842BC, 0x9B7CFF, 0xEEE7FF)
        case .orange: (0xB94E1D, 0xFF9F56, 0xFFF0D9)
        case .green: (0x207D50, 0x66D99A, 0xE3FFE8)
        case .neutral: (0xB9B9C0, 0xDEDEE3, 0xFFFFFF)
        }
    }
}

public enum AetherShadow {
    public static func minimal(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.06 : 0.03), 2, 1)
    }
    public static func resting(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.08 : 0.04), 3, 1)
    }
    public static func floating(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.10 : 0.05), 6, 2)
    }
    public static func sheet(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.12 : 0.06), 10, 4)
    }
}
