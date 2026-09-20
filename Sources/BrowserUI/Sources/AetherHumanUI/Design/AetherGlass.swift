import SwiftUI

public struct AetherGlassBackdrop: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public let radius: CGFloat
    public let interactive: Bool
    public init(radius: CGFloat = AetherMetrics.fieldRadius, interactive: Bool = false) {
        self.radius = radius
        self.interactive = interactive
    }

    @ViewBuilder public var body: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.raised)
        } else if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(interactive ? .regular.interactive() : .regular,
                             in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

public struct AetherGlassGroup<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    @ViewBuilder public var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}
