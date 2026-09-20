import SwiftUI

public enum AetherGlassVariant: Sendable {
    case regular
    case clear
}

public enum AetherGlassTransition: Sendable {
    case identity
    case matchedGeometry
    case materialize

    @available(macOS 26.0, *)
    var value: GlassEffectTransition {
        switch self {
        case .identity: .identity
        case .matchedGeometry: .matchedGeometry
        case .materialize: .materialize
        }
    }
}

public struct AetherGlassBackdrop: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public let radius: CGFloat
    public let interactive: Bool
    public let variant: AetherGlassVariant
    public init(radius: CGFloat = AetherMetrics.fieldRadius, interactive: Bool = false,
                variant: AetherGlassVariant = .regular) {
        self.radius = radius
        self.interactive = interactive
        self.variant = variant
    }

    private var isOpaque: Bool { reduceTransparency || contrast == .increased }

    @ViewBuilder public var body: some View {
        if isOpaque {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.raised)
        } else if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(variant == .clear ? .clear : .regular.interactive(interactive),
                             in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

public struct AetherGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content
    public init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder public var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

public extension View {
    @ViewBuilder
    func aetherGlassMorph<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID,
                                                  transition: AetherGlassTransition = .matchedGeometry) -> some View {
        if #available(macOS 26.0, *) {
            glassEffectID(id, in: namespace).glassEffectTransition(transition.value)
        } else {
            self
        }
    }

    @ViewBuilder
    func aetherGlassUnion<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            glassEffectUnion(id: id, namespace: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func aetherButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func aetherProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
