import SwiftUI

// One shared resolver for every chrome color: toolbar, address bar, address
// text, all navigation/utility/tab icons, focus state, suggestion surfaces,
// sidebar text and hover fills. Nothing computes icon or text colors
// independently.
public enum AetherChromeAppearance: Sendable {
    case light
    case dark

    public var isDark: Bool { self == .dark }

    public var toolbarBG: Color {
        switch self {
        case .light: Color(.sRGB, red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255, opacity: 1)
        case .dark: Color(.sRGB, red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255, opacity: 1)
        }
    }

    public var addressBG: Color {
        switch self {
        case .light: Color(.sRGB, red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255, opacity: 1)
        case .dark: Color(.sRGB, red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255, opacity: 1)
        }
    }

    public var hover: Color {
        switch self {
        case .light: Color(.sRGB, red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF4 / 255, opacity: 0.80)
        case .dark: Color(.sRGB, red: 0x40 / 255, green: 0x40 / 255, blue: 0x40 / 255, opacity: 0.35)
        }
    }

    public var selected: Color {
        switch self {
        case .light: Color(.sRGB, red: 0xE8 / 255, green: 0xE8 / 255, blue: 0xE7 / 255, opacity: 1)
        case .dark: Color(.sRGB, red: 0x2D / 255, green: 0x2D / 255, blue: 0x2D / 255, opacity: 1)
        }
    }

    public var text: Color {
        switch self {
        case .light: Color(.sRGB, red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255, opacity: 1)
        case .dark: Color(.sRGB, red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255, opacity: 1)
        }
    }

    public var icon: Color {
        switch self {
        case .light: Color(.sRGB, red: 0x26 / 255, green: 0x26 / 255, blue: 0x26 / 255, opacity: 1)
        case .dark: Color(.sRGB, red: 0xE5 / 255, green: 0xE5 / 255, blue: 0xE5 / 255, opacity: 1)
        }
    }

    public var secondary: Color {
        switch self {
        case .light: Color(.sRGB, red: 0x73 / 255, green: 0x73 / 255, blue: 0x73 / 255, opacity: 1)
        case .dark: Color(.sRGB, red: 0xA3 / 255, green: 0xA3 / 255, blue: 0xA3 / 255, opacity: 1)
        }
    }

    public var suggestionSurface: Color {
        switch self {
        case .light: Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.94)
        case .dark: Color(.sRGB, red: 0x18 / 255, green: 0x18 / 255, blue: 0x18 / 255, opacity: 0.94)
        }
    }

    public var suggestionSelected: Color {
        switch self {
        case .light: Color(.sRGB, red: 0xEC / 255, green: 0xEC / 255, blue: 0xEB / 255, opacity: 1)
        case .dark: Color(.sRGB, red: 0x2D / 255, green: 0x2D / 255, blue: 0x2D / 255, opacity: 1)
        }
    }

    public var selectedActive: Color {
        switch self {
        case .light: Color(.sRGB, red: 0xD9 / 255, green: 0xD9 / 255, blue: 0xD8 / 255, opacity: 1)
        case .dark: Color(.sRGB, red: 0x2B / 255, green: 0x2B / 255, blue: 0x2B / 255, opacity: 1)
        }
    }

    // Dark glass needs a genuinely dark foundation or material compositing
    // lifts it toward bright grey.
    public var glassFoundation: Color {
        switch self {
        case .light: Color.white.opacity(0.30)
        case .dark: Color(.sRGB, red: 0x10 / 255, green: 0x10 / 255, blue: 0x10 / 255, opacity: 0.72)
        }
    }

    // Sidebar tabs sit on chrome material, never on the website, so their
    // titles must never inherit the site's ink (which goes black on light sites).
    public var sidebarTitle: Color {
        switch self {
        case .light: Color(.sRGB, red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255, opacity: 1)
        case .dark: Color(.sRGB, red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255, opacity: 1)
        }
    }

    public var sidebarSelection: Color {
        switch self {
        case .light: Color.black.opacity(0.06)
        case .dark: Color.white.opacity(0.10)
        }
    }

    public var sidebarHover: Color {
        switch self {
        case .light: Color.black.opacity(0.04)
        case .dark: Color.white.opacity(0.06)
        }
    }
}

public enum AetherChromeAppearanceResolver {
    // WCAG threshold between a light and a dark surface. The dead band keeps
    // pages whose background sits near the boundary from flickering between
    // appearances as subresources load.
    private static let threshold = sqrt((relativeLuminance(0x171717) + 0.05) * (relativeLuminance(0xFAFAFA) + 0.05)) - 0.05
    private static let hysteresis = 0.03

    public static func resolve(siteSurface: UInt?,
                               sitePrefersDark: Bool? = nil,
                               systemDark: Bool,
                               current: AetherChromeAppearance? = nil) -> AetherChromeAppearance {
        guard let hex = siteSurface else {
            if let sitePrefersDark { return sitePrefersDark ? .dark : .light }
            return current ?? (systemDark ? .dark : .light)
        }
        let luminance = relativeLuminance(hex)
        if let current {
            if current == .dark, luminance < threshold + hysteresis { return .dark }
            if current == .light, luminance > threshold - hysteresis { return .light }
        }
        if sitePrefersDark == true, luminance < threshold + hysteresis { return .dark }
        if sitePrefersDark == false, luminance > threshold - hysteresis { return .light }
        return luminance > threshold ? .light : .dark
    }

    public static func relativeLuminance(_ hex: UInt) -> Double {
        func linear(_ component: Double) -> Double {
            let s = component / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let r = linear(Double((hex >> 16) & 255))
        let g = linear(Double((hex >> 8) & 255))
        let b = linear(Double(hex & 255))
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    public static func contrastRatio(_ first: UInt, _ second: UInt) -> Double {
        let a = relativeLuminance(first)
        let b = relativeLuminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

private struct AetherChromeAppearanceKey: EnvironmentKey {
    static let defaultValue: AetherChromeAppearance? = nil
}

extension EnvironmentValues {
    public var aetherChromeAppearance: AetherChromeAppearance? {
        get { self[AetherChromeAppearanceKey.self] }
        set { self[AetherChromeAppearanceKey.self] = newValue }
    }
}

private struct AetherFullscreenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    public var aetherIsFullscreen: Bool {
        get { self[AetherFullscreenKey.self] }
        set { self[AetherFullscreenKey.self] = newValue }
    }
}

private struct AetherTrafficLeadingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 72
}

extension EnvironmentValues {
    public var aetherTrafficLeading: CGFloat {
        get { self[AetherTrafficLeadingKey.self] }
        set { self[AetherTrafficLeadingKey.self] = newValue }
    }
}
