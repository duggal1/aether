import SwiftUI
import UniformTypeIdentifiers

public struct TabItemView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var hovering = false
    let tab: BrowserTab
    let selected: Bool
    let compact: Bool
    let window: BrowserWindowModel
    var namespace: Namespace.ID?

    public init(tab: BrowserTab, selected: Bool, compact: Bool, window: BrowserWindowModel,
                namespace: Namespace.ID? = nil) {
        self.tab = tab; self.selected = selected; self.compact = compact
        self.window = window; self.namespace = namespace
    }

    public var body: some View {
        HStack(spacing: 9) {
            DomainIcon(tab.url, size: 16)
            if !compact {
                Text(tab.title)
                    .font(selected ? AetherType.rowTitle(12) : AetherType.body(12))
                    .lineLimit(1)
                    .foregroundStyle(selected ? theme.ink : theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if tab.loadState == .loading {
                ProgressView().controlSize(.mini).frame(width: 12, height: 12)
            } else if tab.isPinned {
                BrowserIconView(icon: .pin, tint: theme.soft).iconSize(10)
            }
            if hovering && !compact {
                Button { window.close(tab.id) } label: {
                    BrowserIconView(icon: .close, tint: theme.muted).iconSize(10)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .aetherFocusTreatment(radius: 5)
                .focusEffectDisabled()
                .help("Close tab")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, compact ? 8 : 11)
        .frame(height: AetherMetrics.tabHeight)
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
        if selected {
            if let namespace {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.raised)
                    .matchedGeometryEffect(id: "aether.tab.active", in: namespace, isSource: true)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.raised)
            }
        } else if hovering {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.hover)
        }
    }
}
