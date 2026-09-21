import SwiftUI
import UniformTypeIdentifiers

public struct TabItemView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var hovering = false
    @BrowserState private var showPreview = false
    @BrowserState private var hoverToken = 0
    let tab: BrowserTab
    let selected: Bool
    let compact: Bool
    let topFused: Bool
    let isFirst: Bool
    let window: BrowserWindowModel
    var namespace: Namespace.ID?

    public init(tab: BrowserTab, selected: Bool, compact: Bool, window: BrowserWindowModel,
                topFused: Bool = false, isFirst: Bool = false, namespace: Namespace.ID? = nil) {
        self.tab = tab; self.selected = selected; self.compact = compact
        self.window = window; self.topFused = topFused; self.isFirst = isFirst; self.namespace = namespace
    }

    private var isNewTab: Bool {
        guard let url = tab.url, !url.isEmpty else { return true }
        return url == "about:blank"
    }

    private var activeSurface: Color {
        isNewTab ? AetherPalette.activeNewTab(theme.dark) : AetherPalette.activeSite(theme.dark)
    }

    public var body: some View {
        HStack(spacing: topFused ? 10 : 10) {
            DomainIcon(tab.url, size: 16)
                .frame(width: 16, alignment: .center)
            if !compact {
                Text(tab.title)
                    .font(AetherType.emphasis(12))
                    .lineLimit(1)
                    .foregroundStyle(selected ? theme.ink : AetherPalette.tabTitle(theme.dark))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mask {
                        HStack(spacing: 0) {
                            Rectangle().fill(.white)
                            LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 16)
                        }
                    }
                    .offset(y: topFused ? 0.35 : 0.3)
            }
            if tab.loadState == .loading {
                ProgressView().controlSize(.mini).frame(width: 12, height: 12)
            } else if tab.isPinned {
                BrowserIconView(icon: .pin, tint: theme.soft).iconSize(10)
                    .frame(width: 16, alignment: .center)
            }
            if !compact {
                Button { window.close(tab.id) } label: {
                    BrowserIconView(icon: .close, tint: theme.muted).iconSize(9)
                        .frame(width: 16, height: 16)
                        .background(theme.hover.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .aetherPointingCursor()
                .aetherFocusTreatment(radius: 4)
                .focusEffectDisabled()
                .help("Close tab")
                .opacity((hovering || (selected && topFused)) ? 1 : 0)
                .disabled(!hovering && !(selected && topFused))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, compact ? 8 : (topFused ? 13 : 12))
        .frame(height: topFused ? AetherMetrics.tabHeight : 34)
        .frame(width: compact ? 38 : nil)
        .background { selectionBackground }
        .contentShape(Rectangle())
        .onTapGesture { window.select(tab.id) }
        .onHover { value in
            withAnimation(AetherMotion.hover(reduced)) { hovering = value }
            hoverToken += 1
            let token = hoverToken
            if value, !topFused, !compact {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.4))
                    if hovering, hoverToken == token { showPreview = true }
                }
            } else {
                showPreview = false
            }
        }
        .overlay(alignment: .topLeading) {
            if showPreview, !topFused, !compact {
                SidebarHoverPreview(tab: tab, isNewTab: isNewTab)
                    .offset(x: sidebarWidth + 2, y: -8)
                    .zIndex(30)
                    .transition(.opacity)
            }
        }
        .aetherPointingCursor()
        .zIndex(topFused ? (selected ? 5 : 1) : 0)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .contextMenu {
            Button("New Tab") { _ = window.newTab() }
            Button("Duplicate Tab") { window.duplicate(tab.id) }
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { window.togglePin(tab.id) }
            Divider()
            Button("Close Other Tabs") { window.closeOthers(tab.id) }
            Button("Close Tab") { window.close(tab.id) }
        }
        .onDrag { NSItemProvider(object: tab.id.uuidString as NSString) }
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let source = object as? String, let id = UUID(uuidString: source) else { return }
                Task { @MainActor in window.moveTab(id, before: tab.id) }
            }
            return true
        }
        .accessibilityLabel(Text("\(tab.title), \(selected ? "selected tab" : "tab")"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sidebarWidth: CGFloat {
        window.workspace.preferences.transientSidebarWidth ?? window.workspace.preferences.sidebarWidth
    }

    @ViewBuilder private var selectionBackground: some View {
        if topFused {
            if selected {
                if let namespace {
                    fusedActive
                        .matchedGeometryEffect(id: AetherGlassNamespace.tab, in: namespace, isSource: true)
                } else {
                    fusedActive
                }
            } else if hovering {
                UnevenRoundedRectangle(topLeadingRadius: AetherMetrics.fieldRadius + 2,
                                       topTrailingRadius: AetherMetrics.fieldRadius + 2)
                    .fill(AetherPalette.tabHover(theme.dark))
            }
        } else if selected {
            if let namespace {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AetherPalette.canvas(theme.dark))
                    .matchedGeometryEffect(id: AetherGlassNamespace.tabActive, in: namespace, isSource: true)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AetherPalette.canvas(theme.dark))
            }
        } else if hovering {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AetherPalette.selection(theme.dark))
        }
    }

    private var fusedActive: some View {
        FusedTopTabShape(leftFoot: !(isFirst && topFused))
            .fill(activeSurface)
            .overlay {
                FusedTopTabShape(leftFoot: !(isFirst && topFused))
                    .stroke(theme.hairline, lineWidth: 0.5)
            }
    }
}

private struct SidebarHoverPreview: View {
    @Environment(\.aetherTheme) private var theme
    let tab: BrowserTab
    let isNewTab: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tab.title)
                .font(AetherType.emphasis(12))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            Text(isNewTab ? "Ask anything…" : (URL(string: tab.url ?? "")?.host ?? tab.url ?? ""))
                .font(AetherType.body(11))
                .foregroundStyle(theme.muted)
                .lineLimit(1)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 11, trailing: 10))
        .frame(width: 185, alignment: .leading)
        .background(theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AetherMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .aetherGlassShadow(dark: theme.dark)
        .allowsHitTesting(false)
    }
}

struct FusedTopTabShape: Shape {
    var leftFoot = true
    func path(in rect: CGRect) -> Path {
        let rTop: CGFloat = 12
        let fillet: CGFloat = 12
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        var path = Path()
        path.move(to: CGPoint(x: minX + rTop, y: minY))
        path.addLine(to: CGPoint(x: maxX - rTop, y: minY))
        path.addQuadCurve(to: CGPoint(x: maxX, y: minY + rTop), control: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: maxY - fillet))
        path.addQuadCurve(to: CGPoint(x: maxX + fillet, y: maxY), control: CGPoint(x: maxX, y: maxY))
        path.addLine(to: CGPoint(x: leftFoot ? minX - fillet : minX, y: maxY))
        if leftFoot {
            path.addQuadCurve(to: CGPoint(x: minX, y: maxY - fillet), control: CGPoint(x: minX, y: maxY))
        }
        path.addLine(to: CGPoint(x: minX, y: minY + rTop))
        path.addQuadCurve(to: CGPoint(x: minX + rTop, y: minY), control: CGPoint(x: minX, y: minY))
        path.closeSubpath()
        return path
    }
}
