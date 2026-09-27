import AppKit
import SwiftUI

// One shared resolver for every chrome color: toolbar, tab strip, address bar,
// address text, all navigation/utility/tab icons, focus state, suggestion
// surfaces, sidebar veil, sidebar text and hover fills. Nothing computes icon
// or text colors independently.
//
// Two rules keep this coherent:
//   1. The chrome is SOLID. Blur is reserved for floating cards and the sidebar.
//   2. The tab strip and the toolbar are two tones of one surface, and the
//      active tab is filled with the toolbar tone so the junction can't seam.
public enum AetherChromeAppearance: Sendable {
    case light
    case dark

    public var isDark: Bool { self == .dark }

    private static func hex(_ value: UInt, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 255) / 255,
              green: Double((value >> 8) & 255) / 255,
              blue: Double(value & 255) / 255, opacity: alpha)
    }

    /// Toolbar + address row + active tab: one surface, one tone.
    public var toolbarBG: Color {
        switch self {
        case .light: Self.hex(0xF6F4EF)
        case .dark: Self.hex(0x1F1E1C)
        }
    }

    /// The address row is the same surface as the toolbar by design; the active
    /// tab fills with this exact tone so tab and bar read as one piece.
    public var addressBG: Color { toolbarBG }

    /// Tab strip: one step deeper than the toolbar so tabs read as recessed.
    public var stripBG: Color {
        switch self {
        case .light: Self.hex(0xEFEDE8)
        case .dark: Self.hex(0x191817)
        }
    }

    /// Solid search/address field. No material, no glass — a plain surface with
    /// a hairline, the way macOS draws an inset text well.
    public var addressInputBG: Color {
        switch self {
        case .light: Self.hex(0xF3F2EF)
        case .dark: Self.hex(0x2A2825)
        }
    }

    public var fieldBorder: Color {
        switch self {
        case .light: Color.black.opacity(0.09)
        case .dark: Color.white.opacity(0.10)
        }
    }

    public var hairline: Color {
        switch self {
        case .light: Color.black.opacity(0.07)
        case .dark: Color.white.opacity(0.08)
        }
    }

    // There is deliberately no card palette on this type. This enum describes
    // the CHROME — toolbar, tab strip, sidebar. Cards take their colours from
    // `AetherSurfaceStyle`, which knows whether it is over a light website, a
    // dark website, or the start page. Two card palettes is how a light card
    // ended up rendering dark ink, or a dark card rendering light ink.

    /// Sidebar veil over the native sidebar blur: warm off-white in light,
    /// charcoal in dark. Thin on purpose — the native sidebar material already
    /// carries the tone, and a heavy veil on top of it is what made the sidebar
    /// read as a painted opaque slab instead of frosted chrome.
    public var sidebarVeil: Color {
        switch self {
        case .light: Self.hex(0xF5F3EE, 0.64)
        case .dark: Self.hex(0x1B1A18, 0.66)
        }
    }

    /// Fullscreen has no desktop behind the blur, so the veil closes up.
    public var sidebarVeilSolid: Color {
        switch self {
        case .light: Self.hex(0xF5F3EE)
        case .dark: Self.hex(0x1B1A18)
        }
    }

    public var hover: Color {
        switch self {
        case .light: Color.black.opacity(0.05)
        case .dark: Color.white.opacity(0.07)
        }
    }

    public var selected: Color {
        switch self {
        case .light: Color.black.opacity(0.07)
        case .dark: Color.white.opacity(0.12)
        }
    }

    public var text: Color {
        switch self {
        case .light: Self.hex(0x1C1917)
        case .dark: Self.hex(0xFAFAF9)
        }
    }

    public var icon: Color {
        switch self {
        case .light: Self.hex(0x292524)
        case .dark: Self.hex(0xE7E5E4)
        }
    }

    public var secondary: Color {
        switch self {
        case .light: Self.hex(0x78716C)
        case .dark: Self.hex(0xA8A29E)
        }
    }

    public var selectedActive: Color {
        switch self {
        case .light: Color.black.opacity(0.09)
        case .dark: Color.white.opacity(0.14)
        }
    }

    // Sidebar tabs sit on chrome material, never on the website, so their
    // titles must never inherit the site's ink.
    public var sidebarTitle: Color {
        switch self {
        case .light: Self.hex(0x1C1917)
        case .dark: Self.hex(0xF5F5F4)
        }
    }

    public var sidebarSelection: Color {
        switch self {
        case .light: Color.black.opacity(0.07)
        case .dark: Color.white.opacity(0.12)
        }
    }

    public var sidebarHover: Color {
        switch self {
        case .light: Color.black.opacity(0.045)
        case .dark: Color.white.opacity(0.06)
        }
    }
}

// MARK: - One resolver for every floating surface

/// What the floating chrome is drawn over. Not a colour scheme — a page state.
///
/// `homepage` is a page the browser drew itself (start page, results, error): it
/// has a synthetic background, so its cards are solid and its tone follows the
/// window. The two website states are the page's own tone, read from the page.
public enum AetherSurfaceAppearance: Sendable, Equatable {
    case homepage
    case lightWebsite
    case darkWebsite

    public var isDark: Bool { self == .darkWebsite }
    public var isHomepage: Bool { self == .homepage }
}

/// Everything known about the page under the chrome, gathered in one value so no
/// surface invents its own detection.
public struct AetherPageSnapshot: Sendable, Equatable {
    /// The browser drew this page itself: there is no website tone to sample.
    public var isBrowserPage: Bool
    /// The page's own background, when it could be read.
    public var surface: UInt?
    /// The page's declared `color-scheme`, when it declares one.
    public var declaresDark: Bool?

    public init(isBrowserPage: Bool, surface: UInt?, declaresDark: Bool?) {
        self.isBrowserPage = isBrowserPage
        self.surface = surface
        self.declaresDark = declaresDark
    }
}

/// The resolved colours of one floating surface.
///
/// Floating UI never picks its own ink, icon, fill or border: it reads these, so
/// a light card can never end up with light text and a dark card can never end
/// up with dark text. That mismatch is the whole reason the readability kept
/// breaking — there were two palettes and nothing that tied them together.
public struct AetherSurfaceStyle: Sendable, Equatable {
    public let appearance: AetherSurfaceAppearance
    public let isDark: Bool
    public let isHomepage: Bool

    public let primaryText: Color
    public let secondaryText: Color
    public let metadataText: Color
    public let primaryIcon: Color
    public let secondaryIcon: Color

    /// Inset well for a field that sits *inside* a floating card. Translucent on
    /// purpose: an opaque block on a frosted card reads as a hole punched in it.
    public let fieldFill: Color
    public let fieldBorder: Color
    public let controlFill: Color
    public let hoverFill: Color
    public let selectionFill: Color
    public let separator: Color

    public let cardTint: Color
    public let cardBorder: Color
    /// Only the synthetic start page has a solid fill; a website card is blur.
    public let solidFill: Color

    /// Neutral panel action (Import, Export, Clear History). One pair, so the
    /// two buttons beside each other can never invert and stop matching.
    public let panelActionFill: Color
    public let panelActionInk: Color

    public let blurMaterial: NSVisualEffectView.Material
    public let blurAppearance: NSAppearance.Name
}

public enum AetherSurfaceResolver {
    // WCAG threshold between a light and a dark surface. The dead band keeps
    // pages whose background sits near the boundary from flickering between
    // appearances as subresources load.
    private static let threshold = sqrt((relativeLuminance(0x171717) + 0.05) * (relativeLuminance(0xFAFAFA) + 0.05)) - 0.05
    private static let hysteresis = 0.03

    /// The page state. One answer for the whole window.
    public static func appearance(for page: AetherPageSnapshot,
                                  systemDark: Bool,
                                  current: AetherSurfaceAppearance? = nil) -> AetherSurfaceAppearance {
        if page.isBrowserPage { return .homepage }
        guard let hex = page.surface else {
            if let declaresDark = page.declaresDark { return declaresDark ? .darkWebsite : .lightWebsite }
            // Undetermined page tone, and the page declared nothing.
            //
            // This is where the light card used to get lost: the old fallback
            // inherited the DESKTOP's dark scheme, so on a dark Mac every page
            // whose background could not be sampled — gradient headers,
            // transparent bodies, wrapper-painted layouts — resolved dark and
            // rendered a black card on a white website. The chrome sits on the
            // PAGE, not on the desktop, so the desktop's dark is not evidence
            // about the page. The web is overwhelmingly light, so light is the
            // answer that fails safe, and it is only reached when the page
            // refused to say anything at all.
            return .lightWebsite
        }
        let luminance = relativeLuminance(hex)
        if let current {
            if current == .darkWebsite, luminance < threshold + hysteresis { return .darkWebsite }
            if current == .lightWebsite, luminance > threshold - hysteresis { return .lightWebsite }
        }
        if page.declaresDark == true, luminance < threshold + hysteresis { return .darkWebsite }
        if page.declaresDark == false, luminance > threshold - hysteresis { return .lightWebsite }
        return luminance > threshold ? .lightWebsite : .darkWebsite
    }

    /// The tokens every floating surface consumes.
    public static func style(_ appearance: AetherSurfaceAppearance, darkHomepage: Bool) -> AetherSurfaceStyle {
        switch appearance {
        case .homepage: return darkHomepage ? homepageDark : homepageLight
        case .lightWebsite: return lightWebsite
        case .darkWebsite: return darkWebsite
        }
    }

    public static func style(for page: AetherPageSnapshot,
                             systemDark: Bool,
                             current: AetherSurfaceAppearance? = nil) -> AetherSurfaceStyle {
        style(appearance(for: page, systemDark: systemDark, current: current), darkHomepage: systemDark)
    }

    /// For surfaces outside a browser window (Settings), which have no page to
    /// read. Ink only — those cards are solid and never blurred.
    public static func themed(dark: Bool) -> AetherSurfaceStyle {
        style(dark ? .darkWebsite : .lightWebsite, darkHomepage: dark)
    }

    // MARK: Token tables

    private static func hex(_ value: UInt, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 255) / 255,
              green: Double((value >> 8) & 255) / 255,
              blue: Double(value & 255) / 255, opacity: alpha)
    }

    /// Blank start page on a dark window: a solid dark neutral. There is no page
    /// pixel behind the card worth refracting, so a bright blur card here only
    /// ever read as a washed-out slab pasted onto the canvas.
    private static let homepageDark = AetherSurfaceStyle(
        appearance: .homepage,
        isDark: true,
        isHomepage: true,
        primaryText: hex(0xF5F5F7),
        secondaryText: hex(0xA1A1AA),
        metadataText: hex(0xA1A1AA),
        primaryIcon: hex(0xF5F5F7),
        secondaryIcon: hex(0xA1A1AA),
        fieldFill: Color.white.opacity(0.10),
        fieldBorder: Color.white.opacity(0.08),
        controlFill: Color.white.opacity(0.10),
        hoverFill: Color.white.opacity(0.07),
        selectionFill: Color.white.opacity(0.12),
        separator: Color.white.opacity(0.08),
        cardTint: Color.white.opacity(0.10),
        cardBorder: Color.white.opacity(0.08),
        solidFill: hex(0x1F1F1F),
        panelActionFill: Color.white.opacity(0.14),
        panelActionInk: hex(0xFFFFFF),
        blurMaterial: .popover,
        blurAppearance: .aqua
    )

    private static let homepageLight = AetherSurfaceStyle(
        appearance: .homepage,
        isDark: false,
        isHomepage: true,
        primaryText: hex(0x1C1917),
        secondaryText: hex(0x57534E),
        metadataText: hex(0x78716C),
        primaryIcon: hex(0x292524),
        secondaryIcon: hex(0x57534E),
        fieldFill: Color.black.opacity(0.05),
        fieldBorder: Color.black.opacity(0.07),
        controlFill: Color.black.opacity(0.05),
        hoverFill: Color.black.opacity(0.05),
        selectionFill: Color.black.opacity(0.07),
        separator: Color.black.opacity(0.07),
        cardTint: Color.white.opacity(0.60),
        cardBorder: Color.black.opacity(0.07),
        solidFill: hex(0xF6F4EF),
        panelActionFill: hex(0xFAFAFA),
        panelActionInk: hex(0x171717),
        blurMaterial: .popover,
        blurAppearance: .aqua
    )

    /// A card floating over a light website: native light frost plus a
    /// controlled white veil, and dark ink throughout. Light text on a light
    /// blurred card is what made the suggestion panel unreadable.
    ///
    /// White 0.60 over `.popover`/`.aqua` blur: strong enough that website
    /// detail cannot destroy legibility, sheer enough to still read as frosted
    /// glass over the page — never `white.opacity(0.2)`, never a site-tinted
    /// wash. Change this one value to tune every light card at once.
    private static let lightWebsite = AetherSurfaceStyle(
        appearance: .lightWebsite,
        isDark: false,
        isHomepage: false,
        primaryText: hex(0x171717),
        secondaryText: hex(0x404040),
        metadataText: hex(0x525252),
        primaryIcon: hex(0x262626),
        secondaryIcon: hex(0x404040),
        fieldFill: Color.black.opacity(0.06),
        fieldBorder: Color.black.opacity(0.08),
        controlFill: Color.black.opacity(0.05),
        hoverFill: Color.black.opacity(0.05),
        selectionFill: Color.black.opacity(0.08),
        separator: Color.black.opacity(0.08),
        cardTint: Color.white.opacity(0.60),
        cardBorder: Color.black.opacity(0.08),
        solidFill: hex(0xF6F4EF),
        panelActionFill: hex(0xFAFAFA),
        panelActionInk: hex(0x171717),
        blurMaterial: .popover,
        blurAppearance: .aqua
    )

    /// A card floating over a dark website: the dark frost, with off-white ink
    /// that is deliberately brighter than the old muted grey — secondary labels,
    /// URLs and chevrons were disappearing into the blur.
    private static let darkWebsite = AetherSurfaceStyle(
        appearance: .darkWebsite,
        isDark: true,
        isHomepage: false,
        primaryText: hex(0xFFFFFF),
        secondaryText: hex(0xF5F5F5),
        metadataText: hex(0xE5E5E5),
        primaryIcon: hex(0xFFFFFF),
        secondaryIcon: hex(0xE5E5E5),
        fieldFill: Color.white.opacity(0.14),
        fieldBorder: Color.white.opacity(0.10),
        controlFill: Color.white.opacity(0.10),
        hoverFill: Color.white.opacity(0.08),
        selectionFill: Color.white.opacity(0.14),
        separator: Color.white.opacity(0.10),
        cardTint: Color.white.opacity(0.10),
        cardBorder: Color.white.opacity(0.11),
        solidFill: hex(0x1F1F1F),
        panelActionFill: Color.white.opacity(0.14),
        panelActionInk: hex(0xFFFFFF),
        blurMaterial: .hudWindow,
        blurAppearance: .darkAqua
    )

    public static func relativeLuminance(_ hex: UInt) -> Double {
        func linear(_ component: Double) -> Double {
            let s = component / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let r = linear(Double((hex >> 16) & 255))
        let g = linear(Double((hex >> 8) & 255))
        let b = linear(Double(hex & 255))
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    public static func contrastRatio(_ first: UInt, _ second: UInt) -> Double {
        let a = relativeLuminance(first)
        let b = relativeLuminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

private struct AetherChromeAppearanceKey: EnvironmentKey {
    static let defaultValue: AetherChromeAppearance? = nil
}

extension EnvironmentValues {
    public var aetherChromeAppearance: AetherChromeAppearance? {
        get { self[AetherChromeAppearanceKey.self] }
        set { self[AetherChromeAppearanceKey.self] = newValue }
    }
}

private struct AetherFullscreenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    public var aetherIsFullscreen: Bool {
        get { self[AetherFullscreenKey.self] }
        set { self[AetherFullscreenKey.self] = newValue }
    }
}

private struct AetherTrafficLeadingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 72
}

extension EnvironmentValues {
    public var aetherTrafficLeading: CGFloat {
        get { self[AetherTrafficLeadingKey.self] }
        set { self[AetherTrafficLeadingKey.self] = newValue }
    }
}

private struct AetherSurfaceStyleKey: EnvironmentKey {
    static let defaultValue: AetherSurfaceStyle? = nil
}

extension EnvironmentValues {
    /// The floating-surface palette for the page the chrome sits on. Every
    /// dropdown, menu, suggestion panel and dialog reads this one value, so a
    /// card can never disagree with the panel next to it.
    ///
    /// Nil outside a browser window (Settings), where surfaces fall back to the
    /// ambient theme.
    var aetherSurfaceStyle: AetherSurfaceStyle? {
        get { self[AetherSurfaceStyleKey.self] }
        set { self[AetherSurfaceStyleKey.self] = newValue }
    }
}
