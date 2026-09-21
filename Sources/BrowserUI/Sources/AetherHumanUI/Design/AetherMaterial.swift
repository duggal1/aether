import AppKit
import SwiftUI

public enum AetherChromeRole: Sendable {
    case sidebar
    case toolbar
}

public struct AetherChromeBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    public let role: AetherChromeRole

    public init(_ role: AetherChromeRole) { self.role = role }

    private var isOpaque: Bool { reduceTransparency || contrast == .increased }

    private var veilOpacity: Double { role == .sidebar ? 0.76 : 0.88 }

    public var body: some View {
        ZStack {
            if isOpaque {
                theme.canvas
            } else {
                AetherChromeBlur(role: role)
                AetherPalette.chrome(theme.dark).opacity(veilOpacity)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct AetherChromeBlur: NSViewRepresentable {
    typealias NSViewType = NSVisualEffectView
    let role: AetherChromeRole

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { apply(to: view) }

    private func apply(to view: NSVisualEffectView) {
        if role == .sidebar {
            view.material = .sidebar
            view.blendingMode = .behindWindow
        } else {
            view.material = .titlebar
            view.blendingMode = .withinWindow
        }
        view.state = .followsWindowActiveState
        view.isEmphasized = false
    }
}

public struct AetherPopoverBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    public init() {}

    private var isOpaque: Bool { reduceTransparency || contrast == .increased }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: AetherMetrics.menuRadius, style: .continuous) }

    public var body: some View {
        if isOpaque {
            shape.fill(theme.raised).accessibilityHidden(true)
        } else {
            shape.fill(.regularMaterial)
                .overlay { shape.fill(theme.raised.opacity(0.86)) }
                .accessibilityHidden(true)
        }
    }
}
public struct AetherSheetBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    public init() {}

    private var isOpaque: Bool { reduceTransparency || contrast == .increased }

    public var body: some View {
        ZStack {
            if isOpaque {
                theme.raised
            } else {
                AetherStrongInAppBlur()
                theme.raised.opacity(0.88)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct AetherStrongInAppBlur: NSViewRepresentable {
    typealias NSViewType = NSVisualEffectView

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
public struct AetherCardBackground: View {
    @Environment(\.aetherTheme) private var theme
    public let radius: CGFloat
    public init(radius: CGFloat = AetherMetrics.cardRadius) { self.radius = radius }
    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(theme.raised)
            .accessibilityHidden(true)
    }
}

public struct AetherLeadingGlassPanel: View {
    public init() {}
    public var body: some View { AetherPopoverBackground() }
}

public extension View {
    @ViewBuilder
    func aetherGlassShadow(dark: Bool) -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            self.aetherFloatingShadow(dark: dark)
        }
    }
    func aetherRestingShadow(dark: Bool) -> some View {
        let spec = AetherShadow.resting(dark)
        return self.shadow(color: spec.color, radius: spec.radius, y: spec.y)
    }
    func aetherFloatingShadow(dark: Bool) -> some View {
        let spec = AetherShadow.floating(dark)
        return self.shadow(color: spec.color, radius: spec.radius, y: spec.y)
    }
    func aetherSheetShadow(dark: Bool) -> some View {
        let spec = AetherShadow.sheet(dark)
        return self.shadow(color: spec.color, radius: spec.radius, y: spec.y)
    }
}
