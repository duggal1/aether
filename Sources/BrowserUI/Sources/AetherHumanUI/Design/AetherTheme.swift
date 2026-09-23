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
    public var background: Color { AetherPalette.background(dark) }
    public var chrome: Color { AetherPalette.chrome(dark) }
    public var card: Color { AetherPalette.card(dark) }
    public var hover: Color { AetherPalette.hover(dark) }
    public var selected: Color { AetherPalette.selected(dark) }
    public var text: Color { AetherPalette.text(dark) }
    public var textStrong: Color { AetherPalette.textStrong(dark) }
    public var muted: Color { AetherPalette.muted(dark) }
    public var tertiary: Color { AetherPalette.tertiary(dark) }
    public var input: Color { AetherPalette.input(dark) }
    public var dropdownNested: Color { AetherPalette.dropdownNested(dark) }
    public var hairline: Color { AetherPalette.hairline(dark) }
    public var panel: Color { AetherPalette.panel(dark) }
    public var control: Color { AetherPalette.control(dark) }
    public var raised: Color { AetherPalette.raised(dark) }
    public var ink: Color { AetherPalette.ink(dark) }
    public var heading: Color { AetherPalette.heading(dark) }
    public var soft: Color { AetherPalette.soft(dark) }
    public var placeholder: Color { AetherPalette.placeholder(dark) }
    public var suggestionSelected: Color { AetherPalette.suggestionSelected(dark) }
    public var omnibox: Color { AetherPalette.omnibox(dark) }
    public var composer: Color { AetherPalette.composer(dark) }
    public var settingsCanvas: Color { AetherPalette.settingsCanvas(dark) }
    public var settingsCard: Color { AetherPalette.settingsCard(dark) }
    public var inputFocus: Color { AetherPalette.inputFocus(dark) }
    public var tabActive: Color { AetherPalette.tabActive(dark) }
    public var tabHover: Color { AetherPalette.tabHover(dark) }
    public var modal: Color { AetherPalette.modal(dark) }
    public var dialogCard: Color { AetherPalette.dialogCard(dark) }
    public var dialogField: Color { AetherPalette.dialogField(dark) }
    public var focusRing: Color { AetherPalette.focusRing(dark) }
    public var error: Color { AetherPalette.error(dark) }
    public var errorBackground: Color { AetherPalette.errorBackground(dark) }
    public var active: Color { AetherPalette.active(dark) }
    public var focus: Color { AetherPalette.focus(dark) }
    public var settingsRaised: Color { AetherPalette.settingsRaised(dark) }
    public var inset: Color { AetherPalette.inset(dark) }
    public var selection: Color { AetherPalette.selected(dark) }
    public var fieldIcon: Color { AetherPalette.muted(dark) }
    public var faintLine: Color { AetherPalette.hairline(dark) }
    public var canvas: Color { AetherPalette.canvas(dark) }
    public var pinTop: Color { AetherPalette.pinTop(dark) }
    public var pinBottom: Color { AetherPalette.pinBottom(dark) }
    public var profileTop: Color { AetherPalette.profileTop(dark) }
    public var profileBottom: Color { AetherPalette.profileBottom(dark) }
    public var activeSite: Color { AetherPalette.activeSite(dark) }
    public var activeNewTab: Color { AetherPalette.activeNewTab(dark) }
    public var subtle: Color { AetherPalette.subtle(dark) }
    public var surface: Color { AetherPalette.surface(dark) }
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
