import SwiftUI

public enum AetherMotion {
    // Apple liquid motion (Sep 22 editorial foundation): native smooth/snappy
    // curves only. No custom bouncy springs anywhere — bounce is what made
    // every dropdown feel non-native.
    public static let pressScale: CGFloat = 0.987
    public static let hoverScale: CGFloat = 1.0

    public static func hover(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.15) }
    public static func focus(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.21) }
    public static func press(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.11) }
    public static func tab(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.19) }
    public static func selection(_ reduced: Bool) -> Animation? { reduced ? nil : .snappy(duration: 0.10) }
    public static func sidebar(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.22) }
    public static func popover(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.19) }
    public static func dropdown(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.19) }
    public static func panel(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.16) }
    public static func container(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.19) }
    public static func morph(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.24) }
    public static func snappy(_ reduced: Bool) -> Animation? { reduced ? nil : .snappy(duration: 0.12) }
    public static func smooth(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.18) }
    // Coordinated, interruptible cross-fade when the resolved site appearance changes.
    public static func appearance(_ reduced: Bool) -> Animation? { reduced ? nil : .smooth(duration: 0.22) }

    public static func glow(_ reduced: Bool, entering: Bool) -> Animation? {
        if reduced { return .easeOut(duration: 0.15) }
        return .easeOut(duration: entering ? 0.18 : 0.32)
    }

    /// One opening curve for every floating surface in the browser: profile
    /// menu, Search Tabs, three-dot menu, suggestion panel, history, bookmarks
    /// and the dialogs. Restrained on purpose — 160–240 ms perceived, no bounce
    /// and no zooming from nowhere.
    public static func surfaceOpen(_ reduced: Bool) -> Animation? {
        reduced ? nil : .spring(response: 0.22, dampingFraction: 0.88, blendDuration: 0.08)
    }

    /// The matching transition: the card fades in while growing a hair out of
    /// its own trigger, so it reads as emerging from the control that opened it
    /// rather than appearing out of nowhere. Pass the anchor that matches the
    /// trigger — `.topLeading` for the space menu, `.topTrailing` for the
    /// right-side menus, `.top` for the suggestion panel, `.center` for panels.
    public static func surfaceTransition(_ reduced: Bool, anchor: UnitPoint) -> AnyTransition {
        reduced ? .opacity : AnyTransition.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: anchor)),
            removal: .opacity.combined(with: .scale(scale: 0.99, anchor: anchor)))
    }

    public static func panelTransition(_ reduced: Bool) -> AnyTransition {
        surfaceTransition(reduced, anchor: .topTrailing)
    }

    public static func sheetTransition(_ reduced: Bool) -> AnyTransition {
        surfaceTransition(reduced, anchor: .center)
    }

    public static func disclosure(_ reduced: Bool, expanded: Bool) -> AnyTransition {
        reduced ? .opacity : AnyTransition.asymmetric(
            insertion: .scale(scale: 0.97, anchor: expanded ? .top : .topLeading).combined(with: .opacity),
            removal: .scale(scale: 0.99, anchor: expanded ? .top : .topLeading).combined(with: .opacity))
    }

    public static func contentSwap(_ reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .opacity.combined(with: .move(edge: .trailing))
    }

    // Compat shims: these used to add blur-based transitions/animations that
    // smeared text during dropdown morphs. They now resolve to pure Apple
    // opacity/smooth curves — no blur radius anywhere.
    public static func blurMicro(_ reduced: Bool) -> Animation? { reduced ? nil : .easeOut(duration: 0.14) }

    public static func textResolve(_ reduced: Bool) -> Animation? {
        reduced ? nil : .smooth(duration: 0.18)
    }

    public static func blurInOut(_ reduced: Bool) -> AnyTransition {
        reduced ? .opacity : .opacity
    }
}

/// The same opening motion for surfaces the system presents for us — sheets and
/// dialogs. Their frame animation belongs to AppKit, so the card inside picks up
/// the matching emerge-from-center beat.
public struct AetherSurfaceAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var shown = false
    public init() {}

    public func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduced ? 1 : 0.985, anchor: .center)
            .onAppear {
                withAnimation(AetherMotion.surfaceOpen(reduced)) { shown = true }
            }
    }
}

public extension View {
    func aetherSurfaceAppear() -> some View { modifier(AetherSurfaceAppear()) }
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

public struct AetherAnimatedText: View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    let text: String
    public init(text: String) { self.text = text }
    public var body: some View {
        ZStack {
            Text(text)
                .id(text)
                .transition(.opacity)
        }
        .animation(AetherMotion.textResolve(reduced), value: text)
    }
}

public struct AetherFocusedFill: View {
    @Environment(\.isFocused) private var focused
    @Environment(\.aetherTheme) private var theme
    let radius: CGFloat
    public init(radius: CGFloat = AetherMetrics.utilityRadius) { self.radius = radius }
    public var body: some View {
        AetherInteractionSurface(active: focused, radius: radius)
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
    @Environment(\.aetherIsFullscreen) private var fullscreen
    public init() {}
    public func body(content: Content) -> some View {
        // Correction pass §5: custom pointing-hand behavior is disabled while
        // fullscreen is active so no cursor/tracking logic can sit above the
        // toolbar and steal pointer events. Toolbar buttons stay the topmost
        // interactive hit targets. Windowed behavior is unchanged.
        Group {
            if fullscreen {
                content
            } else {
                content.pointerStyle(.link)
            }
        }
    }
}
