import SwiftUI

public struct AetherField: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
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

    private var skin: AetherSurfaceStyle {
        surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
    }

    public var body: some View {
        HStack(spacing: 11) {
            if let icon { BrowserIconView(icon: icon, tint: skin.secondaryIcon).iconSize(16) }
            if secure {
                SecureField(hint, text: $text)
                    .textFieldStyle(.plain)
                    .font(AetherType.body(13))
                    .foregroundStyle(skin.primaryText)
                    .focused($focused)
                    .onSubmit { onSubmit?() }
                    .textContentType(.password)
            } else {
                TextField(hint, text: $text, prompt: Text(hint).foregroundStyle(skin.metadataText))
                    .textFieldStyle(.plain)
                    .font(AetherType.body(13))
                    .foregroundStyle(skin.primaryText)
                    .focused($focused)
                    .onSubmit { onSubmit?() }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: 36)
        .background {
            // A field inside a floating card is a translucent well on the frosted
            // surface, never an opaque block pasted over it.
            AetherSurfaceFieldBackground(radius: AetherMetrics.fieldRadius)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous)
                .strokeBorder(focused ? skin.primaryText.opacity(0.30) : Color.clear, lineWidth: 1)
        }
        .animation(AetherMotion.focus(reduced), value: focused)
    }
}
