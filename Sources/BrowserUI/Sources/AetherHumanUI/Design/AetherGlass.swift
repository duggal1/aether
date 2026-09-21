import SwiftUI

public enum AetherGlassVariant: Sendable {
    case regular
    case clear
}

public struct AetherGlassSurface: View {
    @Environment(\.aetherTheme) private var theme

    public let radius: CGFloat
    public let variant: AetherGlassVariant
    public let interactive: Bool
    public let minimal: Bool

    public init(radius: CGFloat = AetherMetrics.menuRadius, variant: AetherGlassVariant = .regular,
                interactive: Bool = false, minimal: Bool = true) {
        self.radius = radius
        self.variant = variant
        self.interactive = interactive
        self.minimal = minimal
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    public var body: some View {
        Color.clear
            .aetherGlass(variant, in: shape, interactive: interactive)
            .modifier(AetherGlassShadow(enabled: minimal, dark: theme.dark))
            .accessibilityHidden(true)
    }
}

private struct AetherGlassShadow: ViewModifier {
    let enabled: Bool
    let dark: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            let shadow = AetherShadow.minimal(dark)
            content.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
        } else {
            content
        }
    }
}

public extension View {
    @ViewBuilder
    func aetherGlass(_ variant: AetherGlassVariant = .regular,
                     in shape: some Shape, interactive: Bool = false) -> some View {
        switch variant {
        case .regular:
            if interactive {
                glassEffect(.regular.interactive(true), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        case .clear:
            if interactive {
                glassEffect(.clear.interactive(true), in: shape)
            } else {
                glassEffect(.clear, in: shape)
            }
        }
    }

    @ViewBuilder
    func aetherGlassButton() -> some View {
        buttonStyle(.glass).pointerStyle(.link)
    }

    @ViewBuilder
    func aetherGlassProminentButton() -> some View {
        buttonStyle(.glassProminent).pointerStyle(.link)
    }
}

public struct AetherGlassCluster<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainer(spacing: spacing) { content }
    }
}
