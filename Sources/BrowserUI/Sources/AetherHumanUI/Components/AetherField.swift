import SwiftUI

public struct AetherField: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Binding public var text: String
    public var hint: String
    public var icon: BrowserIcon?
    public var onSubmit: (() -> Void)?
    public var horizontalPadding: CGFloat
    public var secure: Bool
    @FocusState private var focused: Bool

    public init(_ hint: String, text: Binding<String>, icon: BrowserIcon? = nil, onSubmit: (() -> Void)? = nil,
                horizontalPadding: CGFloat = 14, secure: Bool = false) {
        self.hint = hint; _text = text; self.icon = icon; self.onSubmit = onSubmit
        self.horizontalPadding = horizontalPadding; self.secure = secure
    }

    public var body: some View {
        HStack(spacing: 11) {
            if let icon { BrowserIconView(icon: icon, tint: theme.fieldIcon).iconSize(16) }
            if secure {
                SecureField(hint, text: $text)
                    .textFieldStyle(.plain)
                    .font(AetherType.body(13))
                    .foregroundStyle(theme.ink)
                    .focused($focused)
                    .onSubmit { onSubmit?() }
                    .textContentType(.password)
            } else {
                TextField(hint, text: $text)
                    .textFieldStyle(.plain)
                    .font(AetherType.body(13))
                    .foregroundStyle(theme.ink)
                    .focused($focused)
                    .onSubmit { onSubmit?() }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: 40)
        .background {
            RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous)
                .fill(theme.dialogField)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous)
                .strokeBorder(focused ? theme.focusRing : Color.clear, lineWidth: 1)
        }
        .animation(AetherMotion.focus(reduced), value: focused)
    }
}
