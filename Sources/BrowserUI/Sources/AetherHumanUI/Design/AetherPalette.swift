import SwiftUI

public enum AetherPalette {
    private static func color(_ hex: UInt, alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255, opacity: alpha)
    }

    public static func canvas(_ dark: Bool) -> Color { color(dark ? 0x1c1917 : 0xffffff) }
    public static func surface(_ dark: Bool) -> Color { color(dark ? 0x231f1d : 0xfafaf9) }
    public static func raised(_ dark: Bool) -> Color { color(dark ? 0x292524 : 0xffffff) }
    public static func subtle(_ dark: Bool) -> Color { color(dark ? 0x292524 : 0xf5f5f4) }
    public static func hover(_ dark: Bool) -> Color { color(dark ? 0x44403c : 0xe7e5e4) }
    public static func ink(_ dark: Bool) -> Color { color(dark ? 0xfafaf9 : 0x1c1917) }
    public static func heading(_ dark: Bool) -> Color { color(dark ? 0xfafaf9 : 0x252324) }
    public static func muted(_ dark: Bool) -> Color { color(dark ? 0xa8a29e : 0x78716c) }
    public static func soft(_ dark: Bool) -> Color { color(0xa8a29e) }
    public static func placeholder(_ dark: Bool) -> Color { color(dark ? 0xa8a29e : 0xb6b0ab) }
    public static func fieldIcon(_ dark: Bool) -> Color { color(dark ? 0xd6d3d1 : 0x57534e) }
    public static func hairline(_ dark: Bool) -> Color { color(dark ? 0xa8a29e : 0xe7e5e4, alpha: dark ? 0.22 : 0.70) }
    public static func faintLine(_ dark: Bool) -> Color { color(dark ? 0xa8a29e : 0xe7e5e4, alpha: dark ? 0.14 : 0.45) }
    public static func selection(_ dark: Bool) -> Color { color(dark ? 0x44403c : 0xe7e5e4) }
    public static func primary(_ dark: Bool) -> Color { color(dark ? 0x44403c : 0xd6d3d1, alpha: dark ? 1 : 0.70) }
    public static func error(_ dark: Bool) -> Color { color(dark ? 0xfca5a5 : 0x991b1b) }
    public static func errorBackground(_ dark: Bool) -> Color { color(dark ? 0x352021 : 0xfffafa) }
    public static func active(_ dark: Bool) -> Color { color(dark ? 0x4ade80 : 0x16a34a) }
}

public enum AetherMetrics {
    public static let cardRadius: CGFloat = 12
    public static let fieldRadius: CGFloat = 8
    public static let utilityRadius: CGFloat = 6
    public static let tabHeight: CGFloat = 34
    public static let chromeHeight: CGFloat = 45
    public static let sidebarWidth: CGFloat = 226
    public static let minSidebarWidth: CGFloat = 188
    public static let maxSidebarWidth: CGFloat = 324
    public static let settingsSidebar: CGFloat = 190
}
