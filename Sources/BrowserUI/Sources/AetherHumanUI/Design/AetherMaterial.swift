import AppKit
import SwiftUI

public enum AetherMaterialRole: Sendable {
    case chrome
    case sidebar
    case settingsSidebar
    case popover
}

public struct AetherNativeMaterial: NSViewRepresentable {
    public typealias NSViewType = NSView
    public let role: AetherMaterialRole

    public init(_ role: AetherMaterialRole) { self.role = role }

    public func makeNSView(context: Context) -> NSView { makeView() }
    public func updateNSView(_ view: NSView, context: Context) {}

    private func makeView() -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 0
            glass.tintColor = nil
            return glass
        }
        let view = NSVisualEffectView()
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        switch role {
        case .chrome:
            view.material = .titlebar
            view.blendingMode = .withinWindow
        case .sidebar, .settingsSidebar, .popover:
            view.material = .sidebar
            view.blendingMode = .behindWindow
        }
        return view
    }
}

public struct AetherChromeBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    public let role: AetherMaterialRole

    public init(_ role: AetherMaterialRole) { self.role = role }

    private var isOpaque: Bool { reduceTransparency || contrast == .increased }

    public var body: some View {
        ZStack {
            if isOpaque { solid } else { AetherNativeMaterial(role) }
        }
        .accessibilityHidden(true)
    }

    private var solid: Color {
        switch role {
        case .chrome: theme.canvas
        case .sidebar, .settingsSidebar, .popover: theme.surface
        }
    }
}

public struct AetherPopoverBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        RoundedRectangle(cornerRadius: AetherMetrics.menuRadius, style: .continuous)
            .fill(theme.raised)
            .accessibilityHidden(true)
    }
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

public extension View {
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
