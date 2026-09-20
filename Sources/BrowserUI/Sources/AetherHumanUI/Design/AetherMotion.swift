import SwiftUI

public enum AetherMotion {
    public static let micro = Animation.spring(duration: 0.16, bounce: 0)
    public static let standard = Animation.spring(duration: 0.28, bounce: 0.08)
    public static let large = Animation.spring(duration: 0.42, bounce: 0.12)
    public static let interactive = Animation.interactiveSpring(response: 0.26, dampingFraction: 0.86)
    public static let pressScale: CGFloat = 0.97

    public static func hover(_ reduced: Bool) -> Animation? { reduced ? nil : micro }
    public static func focus(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.2, bounce: 0.04) }
    public static func tab(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.3, bounce: 0.1) }
    public static func sidebar(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.36, bounce: 0.06) }
    public static func selection(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.22, bounce: 0.08) }
    public static func press(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.12, bounce: 0) }
    public static func popover(_ reduced: Bool) -> Animation? { reduced ? nil : .spring(duration: 0.3, bounce: 0.1) }
    public static func panel(_ reduced: Bool) -> Animation? { reduced ? nil : large }

    public static func glow(_ reduced: Bool, entering: Bool) -> Animation? {
        if reduced { return .easeOut(duration: 0.2) }
        return .easeOut(duration: entering ? 0.22 : 0.36)
    }

    public static func panelTransition(_ reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    public static func sheetTransition(_ reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .scale(scale: 0.97).combined(with: .opacity)
    }
}

public struct AetherPressStyle: ButtonStyle {
    private let reduced: Bool
    public init(reduced: Bool) { self.reduced = reduced }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
    }
}
