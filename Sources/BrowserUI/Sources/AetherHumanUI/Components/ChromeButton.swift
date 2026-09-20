import SwiftUI

public struct ChromeButton: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @BrowserState private var hovering = false
    public let symbol: String
    public let help: String
    public var selected = false
    public var enabled = true
    public var size: CGFloat = 30
    public let action: () -> Void

    public init(_ symbol: String, help: String, selected: Bool = false, enabled: Bool = true,
                size: CGFloat = 30, action: @escaping () -> Void) {
        self.symbol = symbol; self.help = help; self.selected = selected
        self.enabled = enabled; self.size = size; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(enabled ? theme.ink : theme.soft)
                .frame(width: size, height: size)
                .background {
                    if selected {
                        AetherGlassBackdrop(radius: AetherMetrics.utilityRadius, interactive: true)
                    } else {
                        RoundedRectangle(cornerRadius: AetherMetrics.utilityRadius, style: .continuous)
                            .fill(hovering ? theme.hover.opacity(0.78) : .clear)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
        .onHover { value in withAnimation(AetherMotion.hover(reduceMotion)) { hovering = value } }
    }
}
