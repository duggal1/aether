import AppKit
import SwiftUI

public enum AetherMaterialRole {
    case chrome
    case sidebar
    case settingsSidebar
    case popover
}

public struct AetherNativeMaterial: NSViewRepresentable {
    public typealias NSViewType = NSVisualEffectView
    public let role: AetherMaterialRole

    public init(_ role: AetherMaterialRole) { self.role = role }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        configure(view)
        return view
    }

    public func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        switch role {
        case .chrome:
            view.material = .titlebar
            view.blendingMode = .withinWindow
        case .sidebar, .settingsSidebar:
            view.material = .sidebar
            view.blendingMode = .behindWindow
        case .popover:
            view.material = .popover
            view.blendingMode = .behindWindow
        }
    }
}

public struct AetherChromeBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    public let role: AetherMaterialRole

    public init(_ role: AetherMaterialRole) { self.role = role }

    public var body: some View {
        ZStack {
            if reduceTransparency {
                opaqueColor
            } else {
                AetherNativeMaterial(role)
                opaqueColor.opacity(theme.dark ? 0.41 : 0.52)
            }
        }
        .accessibilityHidden(true)
    }

    private var opaqueColor: Color {
        switch role {
        case .chrome: theme.canvas
        case .sidebar, .settingsSidebar, .popover: theme.surface
        }
    }
}

public struct AetherPopoverBackground: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}
    public var body: some View {
        theme.surface.opacity(reduceTransparency ? 1 : (theme.dark ? 0.72 : 0.80))
    }
}
