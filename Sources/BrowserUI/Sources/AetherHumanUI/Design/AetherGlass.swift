import SwiftUI

// Browser-owned content is opaque. Native material belongs only to the sidebar.
public enum AetherGlassVariant: Sendable { case regular, clear }

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

    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(theme.card)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

private struct AetherOpaqueButtonStyle: ButtonStyle {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 11)
            .frame(minHeight: 29)
            .background(
                configuration.isPressed ? theme.selected : (prominent ? theme.hover : theme.card),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 0.5)
            }
            .scaleEffect(configuration.isPressed && !reduced ? 0.985 : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
    }
}

public extension View {
    // Retained for source compatibility. Do not reintroduce transparent glass in browser content.
    func aetherGlass(_ variant: AetherGlassVariant = .regular,
                     in shape: some Shape, interactive: Bool = false) -> some View {
        self.background(AetherGlassSurface(radius: AetherMetrics.menuRadius, variant: variant,
                                          interactive: interactive))
    }

    func aetherGlassButton() -> some View {
        buttonStyle(AetherOpaqueButtonStyle(prominent: false)).pointerStyle(.link)
    }

    func aetherGlassProminentButton() -> some View {
        buttonStyle(AetherOpaqueButtonStyle(prominent: true)).pointerStyle(.link)
    }
}

// A layout container, NOT a glass compositor. Animations are handled by AetherMotion.
public struct AetherGlassCluster<Content: View>: View {
    private let content: Content
    public init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.content = content()
    }
    public var body: some View { content }
}
