import AppKit
import CoreGraphics
import SwiftUI

public enum AetherChromeRole: Sendable {
    case sidebar
    case toolbar
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

struct AetherDitherOverlay: View {
    private static let tile: CGImage? = AetherDitherOverlay.makeTile()

    private static func makeTile() -> CGImage? {
        let side = 64
        var seed: UInt64 = 0x9E3779B97F4A7C15
        var bytes = [UInt8](repeating: 0, count: side * side)
        for index in 0..<(side * side) {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            bytes[index] = UInt8((seed >> 24) & 0xFF)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    var body: some View {
        if let tile = Self.tile {
            Image(decorative: tile, scale: 1, orientation: .up)
                .resizable(resizingMode: .tile)
                .opacity(0.035)
                .blendMode(.overlay)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// Only the sidebar samples macOS native material. All browser-content chrome is opaque.
private struct AetherNativeSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
    }
}

public struct AetherChromeBackground: View {
    @Environment(\.aetherTheme) private var theme
    public let role: AetherChromeRole
    public init(_ role: AetherChromeRole) { self.role = role }

    public var body: some View {
        ZStack {
            if role == .sidebar {
                AetherNativeSidebarMaterial()
                theme.chrome.opacity(theme.dark ? 0.86 : 0.91)
            } else {
                theme.chrome
            }
        }
        .accessibilityHidden(true)
    }
}

public struct AetherPopoverBackground: View {
    @Environment(\.aetherTheme) private var theme
    public init() {}
    public var body: some View {
        RoundedRectangle(cornerRadius: AetherMetrics.menuRadius, style: .continuous)
            .fill(theme.card)
            .overlay {
                RoundedRectangle(cornerRadius: AetherMetrics.menuRadius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 0.5)
            }
    }
}

public struct AetherSheetBackground: View {
    @Environment(\.aetherTheme) private var theme
    public init() {}
    public var body: some View { theme.modal }
}

public struct AetherCardBackground: View {
    @Environment(\.aetherTheme) private var theme
    public let radius: CGFloat
    public init(radius: CGFloat = AetherMetrics.cardRadius) { self.radius = radius }
    public var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(theme.card)
    }
}

public extension View {
    // No synthetic glass glow or layered diffuse shadows inside browser content.
    func aetherGlassShadow(dark: Bool) -> some View { self }
    func aetherDarkGlassShadow(dark: Bool) -> some View { self }
    func aetherRestingShadow(dark: Bool) -> some View { self }
    func aetherFloatingShadow(dark: Bool) -> some View { self }
    func aetherSheetShadow(dark: Bool) -> some View { self }
}
