import SwiftUI

public struct AetherField: View {
    @Environment(\.aetherTheme) private var theme
    @Binding public var text: String
    public var hint: String
    public var icon: String?
    public var onSubmit: (() -> Void)?
    public init(_ hint: String, text: Binding<String>, icon: String? = nil, onSubmit: (() -> Void)? = nil) {
        self.hint = hint; _text = text; self.icon = icon; self.onSubmit = onSubmit
    }
    public var body: some View {
        HStack(spacing: 9) {
            if let icon { Image(systemName: icon).font(.system(size: 13)).foregroundStyle(theme.fieldIcon) }
            TextField(hint, text: $text)
                .font(AetherType.body())
                .textFieldStyle(.plain)
                .foregroundStyle(theme.ink)
                .onSubmit { onSubmit?() }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(theme.raised, in: RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius))
        .overlay(RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius).strokeBorder(theme.line, lineWidth: 1))
    }
}
