import SwiftUI

struct AetherInteractionSurface: View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    var active: Bool
    var radius: CGFloat = 8
    var selected = false
    var hovering = false

    private var fill: Color {
        if let chrome {
            if selected { return hovering ? chrome.selectedActive : chrome.selected }
            return chrome.hover
        }
        return selected ? theme.selection : theme.hover
    }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill)
            .opacity(active ? 1 : 0)
            .allowsHitTesting(false)
            .animation(AetherMotion.hover(reduced), value: active)
    }
}

public struct AetherNeutralButtonStyle: ButtonStyle {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduced
    let prominent: Bool
    public init(prominent: Bool = false) { self.prominent = prominent }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AetherType.body(13))
            .foregroundStyle(prominent ? theme.background : theme.ink)
            .opacity(enabled ? 1 : 0.45)
            .padding(.horizontal, 12)
            .frame(minHeight: 28)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent ? theme.ink : (configuration.isPressed ? theme.selection : theme.card))
            }
            .focusEffectDisabled()
            .modifier(AetherPointingCursor())
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
    }
}

public extension View {
    func aetherButton() -> some View {
        buttonStyle(AetherNeutralButtonStyle(prominent: false)).focusEffectDisabled().pointerStyle(.link)
    }

    func aetherProminentButton() -> some View {
        buttonStyle(AetherNeutralButtonStyle(prominent: true)).focusEffectDisabled().pointerStyle(.link)
    }
}
