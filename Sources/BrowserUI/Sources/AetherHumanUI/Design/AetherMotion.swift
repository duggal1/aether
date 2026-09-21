import SwiftUI

public enum AetherMotion {
    public static let micro = Animation.spring(duration: 0.11, bounce: 0.02)
    public static let standard = Animation.spring(duration: 0.28, bounce: 0.06)
    public static let large = Animation.spring(duration: 0.36, bounce: 0.08)
    public static let snappy = Animation.snappy(duration: 0.20)
    public static let smooth = Animation.smooth(duration: 0.24)
    public static let interactive = Animation.interactiveSpring(response: 0.20, dampingFraction: 0.82)
    public static let liquid = Animation.spring(duration: 0.40, bounce: 0.16)
    public static let liquidSnap = Animation.spring(duration: 0.26, bounce: 0.20)
    public static let pressScale: CGFloat = 0.965
    public static let hoverScale: CGFloat = 1.015

    public static func hover(_ reduced: Bool) -> Animation? { reduced ? nil : micro }
    public static func focus(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.26, bounce: 0.08) }
    public static func tab(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.16, bounce: 0.10) }
    public static func sidebar(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.24, bounce: 0.08) }
    public static func selection(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.16, bounce: 0.12) }
    public static func press(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.10, bounce: 0.0) }
    public static func popover(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.20, bounce: 0.12) }
    public static func dropdown(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.20, bounce: 0.16) }
    public static func panel(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.22, bounce: 0.08) }
    public static func morph(_ reduced: Bool) -> Animation? { reduced ? nil : liquid }
    public static func snappy(_ reduced: Bool) -> Animation? { reduced ? nil : snappy }
    public static func smooth(_ reduced: Bool) -> Animation? { reduced ? nil : smooth }

    public static func glow(_ reduced: Bool, entering: Bool) -> Animation? {
        if reduced { return .easeOut(duration: 0.2) }
        return .easeOut(duration: entering ? 0.24 : 0.40)
    }

    public static func panelTransition(_ reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .opacity
    }

    public static func sheetTransition(_ reduced: Bool) -> AnyTransition {
        reduced ? .opacity : AnyTransition.asymmetric(
            insertion: .scale(scale: 0.94, anchor: .center).combined(with: .opacity),
            removal: .scale(scale: 0.97, anchor: .center).combined(with: .opacity))
    }

    public static func disclosure(_ reduced: Bool, expanded: Bool) -> AnyTransition {
        reduced ? .opacity : AnyTransition.asymmetric(
            insertion: .scale(scale: 0.96, anchor: expanded ? .top : .topLeading).combined(with: .opacity),
            removal: .scale(scale: 0.98, anchor: expanded ? .top : .topLeading).combined(with: .opacity))
    }

    public static func contentSwap(_ reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .opacity.combined(with: .scale(scale: 0.995))
    }
}

public enum AetherGlassNamespace {
    public static let tab = "aether.tab.top"
    public static let tabActive = "aether.tab.active"
    public static let settingsSection = "aether.settings.section"
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
