import SwiftUI

public enum AetherAppearance: String, CaseIterable, Codable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    public var id: String { rawValue }
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public struct AetherTheme {
    public let dark: Bool
    public init(_ scheme: ColorScheme) { dark = scheme == .dark }
    public var canvas: Color { AetherPalette.canvas(dark) }
    public var surface: Color { AetherPalette.surface(dark) }
    public var raised: Color { AetherPalette.raised(dark) }
    public var subtle: Color { AetherPalette.subtle(dark) }
    public var hover: Color { AetherPalette.hover(dark) }
    public var ink: Color { AetherPalette.ink(dark) }
    public var heading: Color { AetherPalette.heading(dark) }
    public var muted: Color { AetherPalette.muted(dark) }
    public var soft: Color { AetherPalette.soft(dark) }
    public var placeholder: Color { AetherPalette.placeholder(dark) }
    public var fieldIcon: Color { AetherPalette.fieldIcon(dark) }
    public var line: Color { AetherPalette.hairline(dark) }
    public var faintLine: Color { AetherPalette.faintLine(dark) }
    public var selection: Color { AetherPalette.selection(dark) }
    public var primary: Color { AetherPalette.primary(dark) }
    public var error: Color { AetherPalette.error(dark) }
    public var errorBackground: Color { AetherPalette.errorBackground(dark) }
    public var active: Color { AetherPalette.active(dark) }
}

private struct AetherThemeKey: EnvironmentKey {
    static let defaultValue = AetherTheme(.light)
}

extension EnvironmentValues {
    public var aetherTheme: AetherTheme {
        get { self[AetherThemeKey.self] }
        set { self[AetherThemeKey.self] = newValue }
    }
}

public struct AetherThemeScope<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content.environment(\.aetherTheme, AetherTheme(scheme))
    }
}
