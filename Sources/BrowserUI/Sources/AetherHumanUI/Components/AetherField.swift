import SwiftUI

public struct AetherField: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Binding public var text: String
    public var hint: String
    public var icon: BrowserIcon?
    public var onSubmit: (() -> Void)?
    @FocusState private var focused: Bool

    public init(_ hint: String, text: Binding<String>, icon: BrowserIcon? = nil, onSubmit: (() -> Void)? = nil) {
        self.hint = hint; _text = text; self.icon = icon; self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 9) {
            if let icon { BrowserIconView(icon: icon, tint: theme.fieldIcon).iconSize(13) }
            TextField(hint, text: $text)
                .textFieldStyle(.plain)
                .font(AetherType.body(13))
                .foregroundStyle(theme.ink)
                .focused($focused)
                .onSubmit { onSubmit?() }
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background {
            RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous)
                .fill(focused ? theme.inputFocus : theme.inset)
        }
        .animation(AetherMotion.focus(reduced), value: focused)
    }
}
