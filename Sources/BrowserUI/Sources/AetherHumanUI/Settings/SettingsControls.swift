import SwiftUI

public struct SettingsToggle: View {
    let title: String
    let subtitle: String?
    let symbol: String?
    @Binding var value: Bool
    public init(_ title: String, subtitle: String? = nil, symbol: String? = nil, value: Binding<Bool>) {
        self.title = title; self.subtitle = subtitle; self.symbol = symbol; _value = value
    }
    public var body: some View {
        AetherRow(title, subtitle: subtitle, symbol: symbol) {
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

public struct SettingsDivider: View {
    @Environment(\.aetherTheme) private var theme
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(theme.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, 12)
    }
}

public struct SettingsHelp: View {
    @Environment(\.aetherTheme) private var theme
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text).font(AetherType.body(12)).foregroundStyle(theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Fresh settings surfaces (frontend rebuild)
//
// One card recipe for every settings section: the exact same native blur the
// browser cards use — dark frost + white text in dark mode — resolved from the
// settings window's own scheme. SF Symbols only: SettingsRow takes a native
// symbol name and nothing else, so a hand-drawn icon can never enter Settings.

/// Blur background shared by cards and dialogs. No shadow — the card adds it.
///
/// Quantum recipe, not the website-card tokens: `.popover` material (hudWindow
/// is always dark, so it can never be the adaptive answer) refracting within
/// the window, plus an explicit tint — dark translucent charcoal
/// (white 0.13 @ 0.55) in dark mode, white 0.60 in light — and a hairline
/// border (white 0.10 / black 0.08). Text still comes from the shared surface
/// skin, so ink stays ultra-readable white in dark mode.
public struct SettingsBlurBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    private let radius: CGFloat
    public init(radius: CGFloat = AetherMetrics.cardRadius) { self.radius = radius }

    public var skin: AetherSurfaceStyle {
        if let surface, !surface.isHomepage { return surface }
        return AetherSurfaceResolver.style(theme.dark ? .darkWebsite : .lightWebsite,
                                            darkHomepage: theme.dark)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    public var body: some View {
        let skin = surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
        ZStack {
            AetherCardBlur(material: .popover,
                           appearance: skin.isDark ? .darkAqua : .aqua,
                           blending: .withinWindow)
                .clipShape(shape)
            shape.fill(skin.isDark ? Color(white: 0.13, opacity: 0.63) : Color(white: 1, opacity: 0.60))
            shape.strokeBorder(skin.isDark ? Color(white: 1, opacity: 0.10) : Color(white: 0, opacity: 0.08), lineWidth: 0.5)
        }
        .compositingGroup()
        .environment(\.colorScheme, skin.isDark ? .dark : .light)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The settings window's own frost. A separate window from the browser, so
/// `.withinWindow` has nothing varied to refract and renders flat — this uses
/// `.behindWindow` to frost the dimmed browser behind the sheet, with the
/// Quantum glass tint over it. Cards then refract this frost within the window.
public struct SettingsWindowBlurBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    public init() {}

    public var body: some View {
        let skin = surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
        let shape = RoundedRectangle(cornerRadius: AetherMetrics.panelRadius, style: .continuous)
        ZStack {
            AetherCardBlur(material: .popover,
                           appearance: skin.isDark ? .darkAqua : .aqua,
                           blending: .behindWindow)
                .clipShape(shape)
            shape.fill(skin.isDark ? Color(white: 0.13, opacity: 0.45) : Color(white: 1, opacity: 0.55))
        }
        .compositingGroup()
        .environment(\.colorScheme, skin.isDark ? .dark : .light)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One settings section card: blur background, hairline, resting shadow.
public struct SettingsCard<Content: View>: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        let dark = surface?.isDark ?? theme.dark
        let elevation = AetherShadow.resting(dark)
        VStack(spacing: 0) { content }
            .background { SettingsBlurBackground() }
            .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.cardRadius, style: .continuous))
            .shadow(color: elevation.color, radius: elevation.radius, y: elevation.y)
    }
}

/// Small bright section header.
public struct SettingsHeader: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    private let title: String
    public init(_ title: String) { self.title = title }

    public var body: some View {
        let skin = surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
        Text(title)
            .font(AetherType.emphasis(12))
            .foregroundStyle(skin.secondaryText)
            .padding(.leading, 2)
    }
}

/// One settings row. Native symbol only.
public struct SettingsRow<Accessory: View>: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    private let title: String
    private let subtitle: String?
    private let symbol: String?
    private let accessory: Accessory

    public init(_ title: String, subtitle: String? = nil, symbol: String? = nil,
                @ViewBuilder accessory: () -> Accessory) {
        self.title = title; self.subtitle = subtitle
        self.symbol = symbol; self.accessory = accessory()
    }

    public var body: some View {
        let skin = surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 13) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(AetherType.symbol(17))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(skin.isDark ? Color.white : skin.primaryIcon)
                        .frame(width: 21, height: 20, alignment: .center)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(AetherType.emphasis(14))
                    .foregroundStyle(skin.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 10)
                accessory
            }
            if let subtitle {
                Text(subtitle)
                    .font(AetherType.body(12))
                    .foregroundStyle(skin.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, symbol == nil ? 0 : 34)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }
}

/// Toggle row on the fresh surfaces.
public struct SettingsSwitchRow: View {
    private let title: String
    private let symbol: String?
    @Binding private var value: Bool
    public init(_ title: String, symbol: String? = nil, value: Binding<Bool>) {
        self.title = title; self.symbol = symbol; _value = value
    }
    public var body: some View {
        SettingsRow(title, symbol: symbol) {
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

public struct AetherColorChoice: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovering = false
    let title: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    public init(title: String, color: Color, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: { action() }) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle().strokeBorder(theme.hairline, lineWidth: 1)
                    }
                    .overlay {
                        if selected {
                            Circle()
                                .strokeBorder(theme.ink, lineWidth: 1.5)
                                .padding(-3)
                        }
                    }
                Text(title)
                    .font(AetherType.body(12))
                    .foregroundStyle(selected ? theme.ink : theme.muted)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                    .opacity(hovering && !selected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aetherPointingCursor()
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(AetherMotion.selection(reduced), value: selected)
        .animation(AetherMotion.hover(reduced), value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
