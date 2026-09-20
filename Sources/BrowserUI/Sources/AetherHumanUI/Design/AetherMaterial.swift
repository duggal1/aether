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

    public var body: some View {
        ZStack {
            theme.canvas
            if !isOpaque { AetherChromeBlur(role: role) }
        }
        .accessibilityHidden(true)
    }
}

private struct AetherChromeBlur: NSViewRepresentable {
    typealias NSViewType = NSVisualEffectView
    let role: AetherChromeRole

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = role == .sidebar ? .sidebar : .titlebar
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
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
        } else if #available(macOS 26.0, *) {
            ZStack {
                shape.fill(theme.raised.opacity(0.55)).accessibilityHidden(true)
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .accessibilityHidden(true)
            }
        } else {
            shape.fill(.regularMaterial).accessibilityHidden(true)
        }
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

public struct AetherLeadingGlassPanel: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    public init() {}

    private var isOpaque: Bool { reduceTransparency || contrast == .increased }
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
    }

    public var body: some View {
        if isOpaque {
            shape.fill(theme.raised).accessibilityHidden(true)
        } else if #available(macOS 26.0, *) {
            ZStack {
                shape.fill(theme.raised.opacity(0.55)).accessibilityHidden(true)
                Color.clear
                    .glassEffect(.regular, in: shape)
                    .accessibilityHidden(true)
            }
        } else {
            shape.fill(.regularMaterial).accessibilityHidden(true)
        }
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
