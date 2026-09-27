import AppKit
import CoreGraphics
import SwiftUI

/// The three chrome surfaces. Toolbar and tab strip are two tones of one piece;
/// the sidebar is the only chrome surface that keeps a blur.
public enum AetherChromeRole: Sendable {
    case sidebar
    case toolbar
    case tabStrip
}

public struct AetherSmoothGradient: View {
    public let stops: [Color]
    public let easing: (Double) -> Double

    public init(stops: [Color], easing: @escaping (Double) -> Double = AetherSmoothGradient.smootherstep) {
        self.stops = stops
        self.easing = easing
    }

    public static func smootherstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    private var resolved: Gradient {
        let count = stops.count
        guard count > 1 else { return Gradient(colors: stops.isEmpty ? [.clear] : stops) }
        let steps = max(48, count * 12)
        var colors: [Color] = []
        colors.reserveCapacity(steps + 1)
        for index in 0...steps {
            let t = easing(Double(index) / Double(steps))
            let position = t * Double(count - 1)
            let lower = min(Int(position), count - 2)
            let local = position - Double(lower)
            colors.append(stops[lower].mix(with: stops[lower + 1], by: local))
        }
        return Gradient(colors: colors)
    }

    public var shapeStyle: LinearGradient {
        LinearGradient(gradient: resolved, startPoint: .top, endPoint: .bottom)
    }

    public var body: some View {
        shapeStyle
    }
}

private extension Color {
    func mix(with other: Color, by amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .black
        return Color(.sRGB,
                     red: Double(a.redComponent) + (Double(b.redComponent) - Double(a.redComponent)) * t,
                     green: Double(a.greenComponent) + (Double(b.greenComponent) - Double(a.greenComponent)) * t,
                     blue: Double(a.blueComponent) + (Double(b.blueComponent) - Double(a.blueComponent)) * t,
                     opacity: Double(a.alphaComponent) + (Double(b.alphaComponent) - Double(a.alphaComponent)) * t)
    }
}

// MARK: - Passthrough primitives

/// Decorative layers must never receive mouse events. A tint, blur, veil or
/// probe that participates in hit-testing swallows clicks meant for the controls
/// above it — that is how toolbar buttons, the new-tab button and panel rows go
/// dead. Subclass this instead of `NSView` for anything that draws but does not
/// interact, and the guarantee is structural rather than per-call-site.
class AetherPassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class AetherPassthroughBlurView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Native AppKit blur behind a floating card. `.withinWindow` on purpose: the
/// card refracts the page it floats over and can never pick up the desktop.
///
/// The material and the appearance come from the resolved surface, never from a
/// local `isDark` guess: a light card is `.popover` in `.aqua`, a dark card is
/// `.hudWindow` in `.darkAqua`, and the two can't drift apart.
struct AetherCardBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let appearance: NSAppearance.Name
    /// `.withinWindow` refracts sibling content (cards over a page or over a
    /// frosted window). `.behindWindow` refracts whatever sits behind the
    /// window itself — required for a top-level background like the settings
    /// window, where within-window has nothing varied to refract and renders
    /// as a flat slab.
    let blending: NSVisualEffectView.BlendingMode

    init(material: NSVisualEffectView.Material,
         appearance: NSAppearance.Name,
         blending: NSVisualEffectView.BlendingMode = .withinWindow) {
        self.material = material
        self.appearance = appearance
        self.blending = blending
    }

    func makeNSView(context: Context) -> AetherPassthroughBlurView {
        let view = AetherPassthroughBlurView()
        view.blendingMode = blending
        view.state = .active
        configure(view)
        return view
    }

    func updateNSView(_ view: AetherPassthroughBlurView, context: Context) {
        view.blendingMode = blending
        configure(view)
    }

    private func configure(_ view: AetherPassthroughBlurView) {
        view.material = material
        view.appearance = NSAppearance(named: appearance)
    }
}

/// Sidebar atmosphere: behind-window material is what makes a native sidebar
/// read as frosted desktop instead of a painted slab. The window is kept
/// non-opaque for exactly this one surface, and the veil on top keeps the tone
/// warm off-white (light) or charcoal (dark).
struct AetherSidebarMaterialView: NSViewRepresentable {
    let dark: Bool
    let fullscreen: Bool

    func makeNSView(context: Context) -> AetherPassthroughBlurView {
        let view = AetherPassthroughBlurView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        configure(view)
        return view
    }

    func updateNSView(_ view: AetherPassthroughBlurView, context: Context) {
        configure(view)
    }

    private func configure(_ view: AetherPassthroughBlurView) {
        // Fullscreen has no desktop behind it, so the solid veil takes over.
        view.isHidden = fullscreen
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}

private extension Color {
    static func aetherHairline(dark: Bool) -> Color {
        dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }
}

// MARK: - Solid field surface

/// Every text input and search well in the app: top omnibox, New Tab search,
/// command palette, History, Bookmarks, dialog fields. Solid on purpose — blur
/// inside a field buys nothing and is what made the chrome look like plastic.
public struct AetherSearchFieldBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var appearance
    private let radius: CGFloat
    public init(radius: CGFloat = AetherMetrics.fieldRadius) { self.radius = radius }
    public var body: some View {
        let dark = appearance?.isDark ?? theme.dark
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(appearance?.addressInputBG ?? AetherPalette.input(dark))
            shape.strokeBorder(appearance?.fieldBorder ?? Color.aetherHairline(dark: dark), lineWidth: 1)
        }
        .environment(\.colorScheme, dark ? .dark : .light)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The inset well for a field that sits *inside* a floating card — panel search
/// fields and dialog fields.
///
/// Translucent on purpose. The chrome's address well is solid, but a solid well
/// on a frosted card reads as an opaque block pasted over glass, which is
/// exactly how the panel search inputs looked.
public struct AetherSurfaceFieldBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var appearance
    @Environment(\.aetherSurfaceStyle) private var surface
    private let radius: CGFloat
    public init(radius: CGFloat = AetherMetrics.fieldRadius) { self.radius = radius }

    public var body: some View {
        let dark = appearance?.isDark ?? theme.dark
        let skin = surface ?? AetherSurfaceResolver.themed(dark: dark)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(skin.fieldFill)
            shape.strokeBorder(skin.fieldBorder, lineWidth: 1)
        }
        .environment(\.colorScheme, dark ? .dark : .light)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The one card recipe

public enum AetherCardDepth: Sendable {
    case resting
    case floating
    case sheet
}

/// Every floating surface in the app — dropdown, menu, suggestion list, popup
/// panel, sheet, credential bubble — is this one recipe: native blur, subtle
/// tint, hairline, one shadow depth, one radius from the shape scale. Cards used
/// to each invent their own material and radius, which is why the app read as a
/// pile of unrelated panels.
struct AetherCardShell: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var appearance
    @Environment(\.aetherSurfaceStyle) private var surface
    private let radius: CGFloat
    private let depth: AetherCardDepth

    init(radius: CGFloat = AetherMetrics.cardRadius, depth: AetherCardDepth = .floating) {
        self.radius = radius
        self.depth = depth
    }

    var body: some View {
        let dark = appearance?.isDark ?? theme.dark
        let skin = surface ?? AetherSurfaceResolver.themed(dark: dark)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let elevation: (color: Color, radius: CGFloat, y: CGFloat) = {
            switch depth {
            case .resting: AetherShadow.resting(skin.isDark)
            case .floating: AetherShadow.floating(skin.isDark)
            case .sheet: AetherShadow.sheet(skin.isDark)
            }
        }()
        ZStack {
            // Over a website the card is native in-window blur, so it reads as
            // glass over the page it belongs to. Over the browser's own start
            // page there is no page tone to refract: a blur there only ever made
            // a bright slab on a dark canvas, so that surface is solid.
            if skin.isHomepage {
                shape.fill(skin.solidFill)
                shape.strokeBorder(skin.cardBorder, lineWidth: 0.5)
            } else {
                AetherCardBlur(material: skin.blurMaterial, appearance: skin.blurAppearance)
                    .clipShape(shape)
                shape.fill(skin.cardTint)
                shape.strokeBorder(skin.cardBorder, lineWidth: 0.5)
            }
        }
        .compositingGroup()
        .shadow(color: elevation.color, radius: elevation.radius, y: elevation.y)
        .environment(\.colorScheme, skin.isDark ? .dark : .light)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// In-window grouped card (settings sections, empty states). Solid, because a
/// blur inside a window over your own canvas is depth theatre, not depth.
struct AetherGroupedCard: View {
    @Environment(\.aetherTheme) private var theme
    private let radius: CGFloat
    init(radius: CGFloat = AetherMetrics.cardRadius) { self.radius = radius }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(theme.settingsCard)
            shape.strokeBorder(theme.hairline, lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Chrome backgrounds

public struct AetherChromeBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var appearance
    @Environment(\.aetherIsFullscreen) private var fullscreen
    public let role: AetherChromeRole
    public init(_ role: AetherChromeRole) { self.role = role }

    public var body: some View {
        let dark = appearance?.isDark ?? theme.dark
        Group {
            switch role {
            case .toolbar, .tabStrip:
                // Solid chrome. No material, no glass, no seam: the tab strip
                // and the toolbar are two tones of one surface and the active
                // tab is filled with the toolbar tone.
                Rectangle().fill(role == .toolbar
                    ? (appearance?.toolbarBG ?? theme.chrome)
                    : (appearance?.stripBG ?? theme.chrome))
            case .sidebar:
                ZStack {
                    AetherSidebarMaterialView(dark: dark, fullscreen: fullscreen)
                    (fullscreen
                        ? (appearance?.sidebarVeilSolid ?? AetherPalette.chrome(dark))
                        : (appearance?.sidebarVeil ?? AetherPalette.chrome(dark)))
                }
            }
        }
        .environment(\.colorScheme, dark ? .dark : .light)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Named surfaces

public struct AetherPopoverBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var appearance
    private let radius: CGFloat
    public init(radius: CGFloat = AetherMetrics.cardRadius) { self.radius = radius }
    public var body: some View {
        AetherCardShell(radius: radius, depth: .resting)
    }
}

public struct AetherSuggestionBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var appearance
    public init() {}
    public var body: some View {
        AetherCardShell(radius: AetherMetrics.cardRadius, depth: .floating)
    }
}

public struct AetherOverlayPanelBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var appearance
    public init() {}
    public var body: some View {
        AetherCardShell(radius: AetherMetrics.panelRadius, depth: .sheet)
    }
}

public struct AetherSheetBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var appearance
    public init() {}
    public var body: some View {
        AetherCardShell(radius: AetherMetrics.panelRadius, depth: .sheet)
    }
}

public struct AetherSettingsWindowBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var appearance
    public init() {}
    public var body: some View {
        AetherCardShell(radius: AetherMetrics.panelRadius, depth: .sheet)
    }
}

public struct AetherSettingsCardBackground: View {
    @Environment(\.aetherTheme) private var theme
    public init() {}
    public var body: some View {
        AetherGroupedCard(radius: AetherMetrics.cardRadius)
    }
}

public struct AetherCardBackground: View {
    @Environment(\.aetherTheme) private var theme
    public let radius: CGFloat
    public init(radius: CGFloat = AetherMetrics.cardRadius) { self.radius = radius }
    public var body: some View {
        AetherGroupedCard(radius: radius)
    }
}

public struct JevQueryBarBackground: View {
    @Environment(\.aetherTheme) private var theme
    public init() {}
    public var body: some View {
        AetherSearchFieldBackground(radius: AetherMetrics.utilityRadius)
    }
}

public extension View {
    /// One elevation ramp for every floating surface, instead of the no-op
    /// shims that left cards looking pasted onto the page.
    func aetherRestingShadow(dark: Bool) -> some View { elevation(AetherShadow.resting(dark)) }
    func aetherFloatingShadow(dark: Bool) -> some View { elevation(AetherShadow.floating(dark)) }
    func aetherSheetShadow(dark: Bool) -> some View { elevation(AetherShadow.sheet(dark)) }
    func aetherGlassShadow(dark: Bool) -> some View { elevation(AetherShadow.resting(dark)) }
    func aetherDarkGlassShadow(dark: Bool) -> some View { elevation(AetherShadow.resting(dark)) }

    private func elevation(_ value: (color: Color, radius: CGFloat, y: CGFloat)) -> some View {
        shadow(color: value.color, radius: value.radius, y: value.y)
    }
}
