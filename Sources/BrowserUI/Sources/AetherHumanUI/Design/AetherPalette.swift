import AppKit
import SwiftUI

public enum AetherNeutral {
    public static let base: UInt = 0x171717
    public static let panel: UInt = 0x1F1F1F
    public static let control: UInt = 0x262626
    public static let raised: UInt = 0x303030
    public static let textPrimary: UInt = 0xFAFAFA
    public static let textSecondary: UInt = 0xF5F5F5
    public static let textMuted: UInt = 0xE5E5E5

    public static let lightBase: UInt = 0xFFFFFF
    public static let lightPanel: UInt = 0xF7F7F7
    public static let lightControl: UInt = 0xEDEDED
    public static let lightRaised: UInt = 0xDEDEDE
    public static let lightOmnibox: UInt = 0xE9E9E9
    public static let lightSettingsCanvas: UInt = 0xEFEFEF
    public static let lightSettingsCard: UInt = 0xFFFFFF
    public static let lightSettingsRaised: UInt = 0xE4E4E4
    public static let lightInputFocus: UInt = 0xD6D6D6
    public static let omnibox: UInt = 0x303030
    public static let settingsCanvas: UInt = 0x1F1F1F
    public static let settingsCard: UInt = 0x262626
    public static let settingsRaised: UInt = 0x2E2E2E
    public static let inputFocus: UInt = 0x353535
    public static let lightTextPrimary: UInt = 0x171717
    public static let lightTextSecondary: UInt = 0x262626
    public static let lightTextMuted: UInt = 0x525252
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

    public static func base(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.base, lightHex: AetherNeutral.lightBase)
    }
    public static func panel(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.panel, lightHex: AetherNeutral.lightPanel)
    }
    public static func control(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.control, lightHex: AetherNeutral.lightControl)
    }
    public static func chrome(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.control, lightHex: AetherNeutral.lightControl)
    }
    public static func tile(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.control, lightHex: AetherNeutral.lightControl)
    }
    public static func pill(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.control, lightHex: AetherNeutral.lightControl)
    }
    public static func card(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.panel, lightHex: AetherNeutral.lightPanel)
    }
    public static func navigation(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textMuted, lightHex: AetherNeutral.lightTextMuted)
    }
    public static func iconDim(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textMuted, lightHex: AetherNeutral.lightTextMuted)
    }
    public static func iconMenu(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textMuted, lightHex: AetherNeutral.lightTextMuted)
    }
    public static func tabTitle(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textSecondary, lightHex: AetherNeutral.lightTextSecondary)
    }
    public static func profile(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textPrimary, lightHex: AetherNeutral.lightTextPrimary)
    }
    public static func chromeHover(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.raised, lightHex: AetherNeutral.lightRaised)
    }
    public static func tabActive(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.base, lightHex: AetherNeutral.lightBase)
    }
    public static func panelBottom(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.panel, lightHex: AetherNeutral.lightPanel)
    }
    public static func canvas(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.base, lightHex: AetherNeutral.lightBase)
    }
    public static func surface(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.base, lightHex: AetherNeutral.lightBase)
    }
    public static func raised(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.panel, lightHex: AetherNeutral.lightPanel)
    }
    public static func inset(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.control, lightHex: AetherNeutral.lightControl)
    }
    public static func subtle(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.control, lightHex: AetherNeutral.lightControl)
    }
    public static func hover(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.control, lightHex: AetherNeutral.lightControl)
    }
    public static func selection(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.raised, lightHex: AetherNeutral.lightRaised)
    }
    public static func primary(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.control, lightHex: AetherNeutral.lightControl)
    }
    public static func ink(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textPrimary, lightHex: AetherNeutral.lightTextPrimary)
    }
    public static func heading(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textPrimary, lightHex: AetherNeutral.lightTextPrimary)
    }
    public static func muted(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textMuted, lightHex: AetherNeutral.lightTextMuted)
    }
    public static func soft(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textMuted, lightHex: AetherNeutral.lightTextMuted)
    }
    public static func placeholder(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textMuted, lightHex: AetherNeutral.lightTextMuted)
    }
    public static func fieldIcon(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textMuted, lightHex: AetherNeutral.lightTextMuted)
    }
    public static func hairline(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.control, lightHex: AetherNeutral.lightControl)
    }
    public static func faintLine(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.control, lightHex: AetherNeutral.lightControl)
    }
    public static func chatBubble(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.raised, lightHex: AetherNeutral.lightRaised)
    }
    public static func chatFill(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.panel, lightHex: AetherNeutral.lightPanel)
    }
    public static func omniboxGlow(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.raised, lightHex: AetherNeutral.lightRaised, alpha: dark ? 0.10 : 0.08)
    }
    public static func accent(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textPrimary, lightHex: AetherNeutral.lightTextPrimary)
    }
    public static func composer(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.panel, lightHex: AetherNeutral.lightPanel)
    }
    public static func omnibox(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.omnibox, lightHex: AetherNeutral.lightOmnibox)
    }
    public static func settingsCanvas(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.settingsCanvas, lightHex: AetherNeutral.lightSettingsCanvas)
    }
    public static func settingsCard(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.settingsCard, lightHex: AetherNeutral.lightSettingsCard)
    }
    public static func settingsRaised(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.settingsRaised, lightHex: AetherNeutral.lightSettingsRaised)
    }
    public static func inputFocus(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.inputFocus, lightHex: AetherNeutral.lightInputFocus)
    }
    public static func suggestionSelected(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.raised, lightHex: AetherNeutral.lightRaised)
    }
    public static func modal(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.panel, lightHex: AetherNeutral.lightPanel)
    }
    public static func tabHover(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.raised, lightHex: AetherNeutral.lightRaised)
    }
    public static func profileTop(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.raised, lightHex: AetherNeutral.lightRaised)
    }
    public static func profileBottom(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.raised, lightHex: AetherNeutral.lightRaised)
    }
    public static func activeNewTab(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.base, lightHex: AetherNeutral.lightBase)
    }
    public static func activeSite(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.base, lightHex: AetherNeutral.lightBase)
    }
    public static func pinTop(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.control, lightHex: AetherNeutral.lightControl)
    }
    public static func pinBottom(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.control, lightHex: AetherNeutral.lightControl)
    }
    public static func pageTop(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.base, lightHex: AetherNeutral.lightBase)
    }
    public static func pageMiddle(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.base, lightHex: AetherNeutral.lightBase)
    }
    public static func pageBottom(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.base, lightHex: AetherNeutral.lightBase)
    }
    public static func error(_ dark: Bool) -> Color {
        color(dark ? 0xE5A0A0 : 0x8A1F1F)
    }
    public static func errorBackground(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.panel, lightHex: AetherNeutral.lightPanel)
    }
    public static func active(_ dark: Bool) -> Color {
        color(dark ? 0x7FB98C : 0x2F6B3C)
    }
    public static func focus(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.raised, lightHex: AetherNeutral.lightRaised)
    }
    public static func glowCore(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textPrimary, lightHex: AetherNeutral.lightTextPrimary)
    }
    public static func glowMid(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.textMuted, lightHex: AetherNeutral.lightTextMuted)
    }
    public static func glowOuter(_ dark: Bool) -> Color {
        neutral(dark, darkHex: AetherNeutral.raised, lightHex: AetherNeutral.lightRaised)
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

public enum AetherProgressColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case violet = "Violet"
    case neutral = "Neutral"
    case blue = "Blue"
    case green = "Green"
    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .violet: Color(red: 0xA2 / 255, green: 0x94 / 255, blue: 0xE5 / 255)
        case .neutral: Color(red: 0xE5 / 255, green: 0xE5 / 255, blue: 0xE5 / 255)
        case .blue: Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
        case .green: Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
        }
    }

    public var gradientTrio: (UInt, UInt, UInt) {
        switch self {
        case .violet: (0x8460EF, 0xB8A0FF, 0xE9DFFF)
        case .neutral: (0xB9B9C0, 0xDEDEE3, 0xFFFFFF)
        case .blue: (0x0A84FF, 0x6CB4FF, 0xDCEEFF)
        case .green: (0x30D158, 0x7EE2A0, 0xDFF7E7)
        }
    }
}

public enum AetherShadow {
    public static func resting(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.08 : 0.04), 3, 1)
    }
    public static func floating(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.11 : 0.06), 8, 3)
    }
    public static func sheet(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.15 : 0.08), 14, 5)
    }
}
