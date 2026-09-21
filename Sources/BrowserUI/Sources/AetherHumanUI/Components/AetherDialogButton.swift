import SwiftUI

public struct AetherDialogButtonStyle: ButtonStyle {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    public enum Kind { case cancel, primary }
    let kind: Kind
    let reduced: Bool
    public init(kind: Kind, reduced: Bool) { self.kind = kind; self.reduced = reduced }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AetherType.body(13))
            .foregroundStyle(foreground(configuration))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(background(configuration),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .aetherPointingCursor()
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
    }

    private func background(_ configuration: Configuration) -> Color {
        if !isEnabled { return theme.control }
        switch kind {
        case .cancel: return configuration.isPressed ? theme.settingsRaised : theme.control
        case .primary: return configuration.isPressed ? Color(red: 0xDD / 255, green: 0xDD / 255, blue: 0xDD / 255) : Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255)
        }
    }

    private func foreground(_ configuration: Configuration) -> Color {
        if !isEnabled { return theme.soft }
        switch kind {
        case .cancel: return theme.ink
        case .primary: return Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255)
        }
    }
}
