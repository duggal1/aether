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
    public init(tab: BrowserTab, selected: Bool, compact: Bool, window: BrowserWindowModel) {
        self.tab = tab; self.selected = selected; self.compact = compact; self.window = window
    }
    public var body: some View {
        HStack(spacing: 9) {
            DomainIcon(tab.url, size: 16)
            if !compact {
                Text(tab.title).font(AetherType.medium(12)).lineLimit(1)
                    .foregroundStyle(selected ? theme.ink : theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if tab.loadState == .loading {
                ProgressView().controlSize(.mini).frame(width: 13, height: 13)
            } else if tab.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(theme.soft)
            }
            if hovering && !compact {
                Button { window.close(tab.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .medium))
                        .frame(width: 17, height: 17)
                }
                .buttonStyle(.plain).foregroundStyle(theme.muted).help("Close tab")
            }
        }
        .padding(.horizontal, compact ? 8 : 11)
        .frame(height: AetherMetrics.tabHeight)
        .frame(width: compact ? 38 : nil)
        .background {
            if selected && window.arrangement == .top {
                AetherGlassBackdrop(radius: 8)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? theme.selection : hovering ? theme.subtle : .clear)
            }
        }
        .overlay(alignment: .leading) {
            if selected && window.arrangement == .sidebar {
                Capsule().fill(theme.muted.opacity(0.72))
                    .frame(width: 2, height: 17).padding(.leading, 2)
            }
        }
        .overlay(alignment: .bottom) {
            if selected && window.arrangement == .top {
                Capsule().fill(theme.muted.opacity(0.6)).frame(height: 1).padding(.horizontal, 15)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { window.select(tab.id) }
        .onHover { value in withAnimation(AetherMotion.hover(reduced)) { hovering = value } }
        .animation(AetherMotion.selection(reduced), value: selected)
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
        .accessibilityLabel("\(tab.title), \(selected ? "selected" : "tab")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
