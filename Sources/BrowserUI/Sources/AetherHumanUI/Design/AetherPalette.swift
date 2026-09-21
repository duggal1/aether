import AppKit
import SwiftUI

public enum AetherPalette {
    private static func color(_ hex: UInt, alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255, opacity: alpha)
    }

    public static func chrome(_ dark: Bool) -> Color { color(dark ? 0x272530 : 0xededf2) }
    public static func tile(_ dark: Bool) -> Color { color(dark ? 0x3d3d47 : 0xe5e5eb) }
    public static func navigation(_ dark: Bool) -> Color { color(dark ? 0xd6d5da : 0x353540) }
    public static func panelBottom(_ dark: Bool) -> Color { color(dark ? 0x232323 : 0xf7f7fa) }
    public static func canvas(_ dark: Bool) -> Color { color(dark ? 0x1a191e : 0xffffff) }
    public static func surface(_ dark: Bool) -> Color { color(dark ? 0x28282d : 0xf2f2f5) }
    public static func raised(_ dark: Bool) -> Color { color(dark ? 0x28282d : 0xf2f2f5) }
    public static func inset(_ dark: Bool) -> Color { color(dark ? 0x1a191e : 0xffffff) }
    public static func subtle(_ dark: Bool) -> Color { color(dark ? 0x36363e : 0xf2f2f5) }
    public static func hover(_ dark: Bool) -> Color { color(dark ? 0x36363e : 0xe5e5eb) }
    public static func selection(_ dark: Bool) -> Color { color(dark ? 0x36363e : 0xe5e5eb) }
    public static func primary(_ dark: Bool) -> Color { color(dark ? 0x36363e : 0xe5e5eb) }
    public static func ink(_ dark: Bool) -> Color { color(dark ? 0xf2f2f5 : 0x1a191e) }
    public static func heading(_ dark: Bool) -> Color { color(dark ? 0xf2f2f5 : 0x1a191e) }
    public static func muted(_ dark: Bool) -> Color { color(dark ? 0xb4b3bd : 0x85848e) }
    public static func soft(_ dark: Bool) -> Color { color(dark ? 0x85848e : 0xb4b3bd) }
    public static func placeholder(_ dark: Bool) -> Color { color(dark ? 0xb4b3bd : 0x85848e) }
    public static func fieldIcon(_ dark: Bool) -> Color { color(dark ? 0xb4b3bd : 0x85848e) }
    public static func hairline(_ dark: Bool) -> Color { color(dark ? 0xf2f2f5 : 0x1a191e, alpha: 0.08) }
    public static func faintLine(_ dark: Bool) -> Color { color(dark ? 0xf2f2f5 : 0x1a191e, alpha: 0.06) }
    public static func error(_ dark: Bool) -> Color { color(dark ? 0xfca5a5 : 0x991b1b) }
    public static func errorBackground(_ dark: Bool) -> Color { color(dark ? 0x352021 : 0xfffafa) }
    public static func active(_ dark: Bool) -> Color { color(dark ? 0x4ade80 : 0x16a34a) }
    public static func focus(_ dark: Bool) -> Color { color(dark ? 0xf2f2f5 : 0x1a191e, alpha: 0.14) }
    public static func glowCore(_ dark: Bool) -> Color { dark ? .white : color(0x8b7bf2) }
    public static func glowMid(_ dark: Bool) -> Color { dark ? color(0xe9eff8) : color(0x5f8df5) }
    public static func glowOuter(_ dark: Bool) -> Color { dark ? color(0xd8dfea) : color(0xb072e6) }
}

public enum AetherMetrics {
    public static let cardRadius: CGFloat = 10
    public static let fieldRadius: CGFloat = 8
    public static let utilityRadius: CGFloat = 6
    public static let menuRadius: CGFloat = 12
    public static let panelRadius: CGFloat = 16
    public static let tabHeight: CGFloat = 33
    public static let rowHeight: CGFloat = 36
    public static let chromeHeight: CGFloat = 42
    public static let iconCanvas: CGFloat = 20
    public static let tapTarget: CGFloat = 44
    public static let sidebarWidth: CGFloat = 190
    public static let minSidebarWidth: CGFloat = 188
    public static let maxSidebarWidth: CGFloat = 324
    public static let settingsSidebar: CGFloat = 218
}

public enum AetherProgressColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case violet = "Violet"
    case blue = "Blue"
    case green = "Green"
    case orange = "Orange"
    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .violet: Color(red: 0xA2 / 255, green: 0x94 / 255, blue: 0xE5 / 255)
        case .blue: Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
        case .green: Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
        case .orange: Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
        }
    }
}

public enum AetherShadow {
    public static func resting(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.10 : 0.04), 3, 1)
    }
    public static func floating(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.18 : 0.08), 10, 3)
    }
    public static func sheet(_ dark: Bool) -> (color: Color, radius: CGFloat, y: CGFloat) {
        (Color.black.opacity(dark ? 0.22 : 0.10), 14, 5)
    }
}
