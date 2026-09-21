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
    public var iconSize: CGFloat = 16
    public let action: () -> Void

    public init(_ icon: BrowserIcon, help: String, selected: Bool = false, enabled: Bool = true,
                size: CGFloat = 30, iconSize: CGFloat = 16, action: @escaping () -> Void) {
        self.icon = icon; self.help = help; self.selected = selected
        self.enabled = enabled; self.size = size; self.iconSize = iconSize; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            BrowserIconView(icon: icon, tint: tint)
                .iconSize(iconSize)
                .frame(width: size, height: size)
                .background { surface }
        }
        .buttonStyle(AetherPressStyle(reduced: reduceMotion))
        .focusEffectDisabled()
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
        .onHover { value in withAnimation(AetherMotion.hover(reduceMotion)) { hovering = value } }
    }

    @ViewBuilder private var surface: some View {
        if enabled && (hovering || selected) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.hover)
        }
    }

    private var tint: Color {
        guard enabled else { return theme.soft }
        return hovering || selected ? theme.ink : theme.muted
    }
}
