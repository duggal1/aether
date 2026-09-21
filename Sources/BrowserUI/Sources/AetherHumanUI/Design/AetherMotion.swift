import SwiftUI

public enum AetherMotion {
    public static let pressScale: CGFloat = 0.96
    public static let hoverScale: CGFloat = 1.01

    public static func hover(_ reduced: Bool) -> Animation? { reduced ? nil : .snappy(duration: 0.08) }
    public static func focus(_ reduced: Bool) -> Animation? { reduced ? nil : .snappy(duration: 0.10) }
    public static func press(_ reduced: Bool) -> Animation? { reduced ? nil : .snappy(duration: 0.06) }
    public static func tab(_ reduced: Bool) -> Animation? { reduced ? nil : .snappy(duration: 0.12) }
    public static func selection(_ reduced: Bool) -> Animation? { reduced ? nil : .snappy(duration: 0.10) }
    public static func sidebar(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.18) }
    public static func popover(_ reduced: Bool) -> Animation? { reduced ? nil : .snappy(duration: 0.14) }
    public static func dropdown(_ reduced: Bool) -> Animation? { reduced ? nil : .snappy(duration: 0.12) }
    public static func panel(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.16) }
    public static func morph(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.28, bounce: 0.12) }
    public static func snappy(_ reduced: Bool) -> Animation? { reduced ? nil : .snappy(duration: 0.12) }
    public static func smooth(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.18) }

    public static func glow(_ reduced: Bool, entering: Bool) -> Animation? {
        if reduced { return .easeOut(duration: 0.15) }
        return .easeOut(duration: entering ? 0.18 : 0.32)
    }

    public static func panelTransition(_ reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .opacity
    }

    public static func sheetTransition(_ reduced: Bool) -> AnyTransition {
        reduced ? .opacity : AnyTransition.asymmetric(
            insertion: .scale(scale: 0.96, anchor: .center).combined(with: .opacity),
            removal: .scale(scale: 0.98, anchor: .center).combined(with: .opacity))
    }

    public static func disclosure(_ reduced: Bool, expanded: Bool) -> AnyTransition {
        reduced ? .opacity : AnyTransition.asymmetric(
            insertion: .scale(scale: 0.97, anchor: expanded ? .top : .topLeading).combined(with: .opacity),
            removal: .scale(scale: 0.99, anchor: expanded ? .top : .topLeading).combined(with: .opacity))
    }

    public static func contentSwap(_ reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .opacity.combined(with: .scale(scale: 0.998))
    }
}

public enum AetherGlassNamespace {
    public static let tab = "aether.tab.top"
    public static let tabActive = "aether.tab.active"
    public static let settingsSection = "aether.settings.section"
    public static let profileCluster = "aether.toolbar.profile-cluster"
}

public struct AetherPressStyle: ButtonStyle {
    private let reduced: Bool
    public init(reduced: Bool) { self.reduced = reduced }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { AetherFocusedFill(radius: AetherMetrics.utilityRadius) }
            .focusEffectDisabled()
            .modifier(AetherPointingCursor())
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
    }
}

public struct AetherFocusedFill: View {
    @Environment(\.isFocused) private var focused
    @Environment(\.aetherTheme) private var theme
    let radius: CGFloat
    public init(radius: CGFloat = AetherMetrics.utilityRadius) { self.radius = radius }
    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(focused ? theme.hover : .clear)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

public extension View {
    func aetherFocusTreatment(radius: CGFloat = AetherMetrics.utilityRadius) -> some View {
        self.background { AetherFocusedFill(radius: radius) }
            .focusEffectDisabled()
    }

    func aetherPointingCursor() -> some View {
        self.modifier(AetherPointingCursor())
    }

    func aetherHoverLift(reduced: Bool, active: Bool) -> some View {
        self.scaleEffect(active && !reduced ? AetherMotion.hoverScale : 1)
            .animation(AetherMotion.hover(reduced), value: active)
    }
}

public struct AetherPointingCursor: ViewModifier {
    public init() {}
    public func body(content: Content) -> some View {
        content.pointerStyle(.link)
    }
}
