import SwiftUI
import UniformTypeIdentifiers

public struct TabItemView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var hovering = false
    let tab: BrowserTab
    let selected: Bool
    let compact: Bool
    let topFused: Bool
    let window: BrowserWindowModel
    var namespace: Namespace.ID?

    public init(tab: BrowserTab, selected: Bool, compact: Bool, window: BrowserWindowModel,
                topFused: Bool = false, namespace: Namespace.ID? = nil) {
        self.tab = tab; self.selected = selected; self.compact = compact
        self.window = window; self.topFused = topFused; self.namespace = namespace
    }

    public var body: some View {
        HStack(spacing: topFused ? 7 : 8) {
            DomainIcon(tab.url, size: 16)
            if !compact {
                Text(tab.title)
                    .font(AetherType.body(13))
                    .lineLimit(1)
                    .foregroundStyle(selected ? theme.ink : AetherPalette.navigation(theme.dark))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .mask {
                        HStack(spacing: 0) {
                            Rectangle().fill(.white)
                            LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 16)
                        }
                    }
            }
            if tab.loadState == .loading {
                ProgressView().controlSize(.mini).frame(width: 12, height: 12)
            } else if tab.isPinned {
                BrowserIconView(icon: .pin, tint: theme.soft).iconSize(10)
            }
            if (hovering || (selected && topFused)) && !compact {
                Button { window.close(tab.id) } label: {
                    BrowserIconView(icon: .close, tint: theme.muted).iconSize(11)
                        .frame(width: 22, height: 22)
                        .background(theme.hover.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .aetherFocusTreatment(radius: 5)
                .focusEffectDisabled()
                .help("Close tab")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, compact ? 8 : (topFused ? 10 : 9))
        .frame(height: topFused ? 39 : AetherMetrics.tabHeight)
        .frame(width: compact ? 38 : nil)
        .background { selectionBackground }
        .contentShape(Rectangle())
        .onTapGesture { window.select(tab.id) }
        .onHover { value in withAnimation(AetherMotion.hover(reduced)) { hovering = value } }
        .aetherPointingCursor()
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

    @ViewBuilder private var selectionBackground: some View {
        if topFused {
            if selected {
                if let namespace {
                    fusedActive
                        .matchedGeometryEffect(id: "aether.tab.top", in: namespace, isSource: true)
                } else {
                    fusedActive
                }
            } else if hovering {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(theme.hover)
            }
        } else if selected {
            if let namespace {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.canvas)
                    .matchedGeometryEffect(id: "aether.tab.active", in: namespace, isSource: true)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.canvas)
            }
        } else if hovering {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.hover)
        }
    }

    private var fusedActive: some View {
        FusedTopTabShape()
            .fill(theme.canvas)
            .overlay {
                FusedTopTabShape()
                    .stroke(LinearGradient(colors: [.white.opacity(0.23), .white.opacity(0.14), .clear],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.5)
            }
    }
}

struct FusedTopTabShape: Shape {
    func path(in rect: CGRect) -> Path {
        let rTop: CGFloat = 9
        let fillet: CGFloat = 15
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
        path.addLine(to: CGPoint(x: minX - fillet, y: maxY))
        path.addQuadCurve(to: CGPoint(x: minX, y: maxY - fillet), control: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: minX, y: minY + rTop))
        path.addQuadCurve(to: CGPoint(x: minX + rTop, y: minY), control: CGPoint(x: minX, y: minY))
        path.closeSubpath()
        return path
    }
}
