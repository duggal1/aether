import SwiftUI

public struct AetherViewportGlow: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @State private var breathing = false

    public let phase: AetherNavigationPhase
    public let instant: Bool
    public let cornerRadius: CGFloat

    public init(phase: AetherNavigationPhase, instant: Bool = false, cornerRadius: CGFloat = 0) {
        self.phase = phase
        self.instant = instant
        self.cornerRadius = cornerRadius
    }

    private var dark: Bool { scheme == .dark }
    private var isActive: Bool { phase.isActive }
    private var canAnimate: Bool { isActive && !reduceMotion && activeState == .key }

    private var intensity: Double {
        let base: Double
        switch phase {
        case .idle: base = 0
        case .started: base = 0.60
        case .awaitingContent: base = 0.42
        case .contentVisible: base = 0.20
        case .failed: base = 0.16
        }
        return instant ? base * 0.35 : base
    }

    public var body: some View {
        GeometryReader { proxy in
            let band = max(10, min(30, min(proxy.size.width, proxy.size.height) * 0.07))
            ZStack {
                ForEach(AetherGlowEdge.allCases, id: \.self) { edge in
                    edgeBand(edge, band: band, size: proxy.size)
                }
                ForEach(AetherGlowCorner.allCases, id: \.self) { corner in
                    cornerLight(corner, band: band, size: proxy.size)
                }
            }
        }
        .opacity(intensity * (breathing ? 1 : 0.82))
        .blendMode(dark ? .plusLighter : .normal)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(AetherMotion.glow(reduceMotion, entering: isActive), value: phase)
        .onAppear { updateBreathing() }
        .onChange(of: canAnimate) { _, _ in updateBreathing() }
    }

    private func updateBreathing() {
        if canAnimate {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathing = true }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { breathing = false }
        }
    }

    private func edgeBand(_ edge: AetherGlowEdge, band: CGFloat, size: CGSize) -> some View {
        LinearGradient(colors: [AetherPalette.glowCore(dark).opacity(0.85),
                                AetherPalette.glowMid(dark).opacity(0.34),
                                .clear],
                       startPoint: edge.startPoint, endPoint: edge.endPoint)
            .frame(width: edge.isHorizontal ? size.width : band,
                   height: edge.isHorizontal ? band : size.height)
            .blur(radius: band * 0.30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.alignment)
    }

    private func cornerLight(_ corner: AetherGlowCorner, band: CGFloat, size: CGSize) -> some View {
        let extent = band * 1.6
        return RadialGradient(colors: [AetherPalette.glowCore(dark).opacity(0.72),
                                       AetherPalette.glowOuter(dark).opacity(0.26),
                                       .clear],
                              center: corner.center, startRadius: 0, endRadius: extent)
            .frame(width: extent, height: extent)
            .blur(radius: band * 0.24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
    }
}

private enum AetherGlowEdge: CaseIterable {
    case top, bottom, leading, trailing

    var isHorizontal: Bool { self == .top || self == .bottom }

    var alignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    var startPoint: UnitPoint {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    var endPoint: UnitPoint {
        switch self {
        case .top: .bottom
        case .bottom: .top
        case .leading: .trailing
        case .trailing: .leading
        }
    }
}

private enum AetherGlowCorner: CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }

    var center: UnitPoint {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }
}
