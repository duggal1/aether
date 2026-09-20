import SwiftUI

public struct ChromeButton: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @BrowserState private var hovering = false
    public let icon: BrowserIcon
    public let help: String
    public var selected = false
    public var enabled = true
    public var size: CGFloat = 30
    public let action: () -> Void

    public init(_ icon: BrowserIcon, help: String, selected: Bool = false, enabled: Bool = true,
                size: CGFloat = 30, action: @escaping () -> Void) {
        self.icon = icon; self.help = help; self.selected = selected
        self.enabled = enabled; self.size = size; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            BrowserIconView(icon: icon, tint: tint)
                .iconSize(15)
                .frame(width: size, height: size)
                .background {
                    if enabled && (hovering || selected) {
                        Circle().fill(theme.hover)
                    }
                }
        }
        .buttonStyle(AetherPressStyle(reduced: reduceMotion))
        .focusEffectDisabled()
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
        .onHover { value in withAnimation(AetherMotion.hover(reduceMotion)) { hovering = value } }
    }

    private var tint: Color {
        guard enabled else { return theme.soft }
        return hovering || selected ? theme.ink : theme.muted
    }
}
