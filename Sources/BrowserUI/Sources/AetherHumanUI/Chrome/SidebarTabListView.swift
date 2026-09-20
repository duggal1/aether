import SwiftUI

public struct SidebarTabListView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var addingShortcut = false
    @Namespace private var tabGlass
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ProfileSwitcherView(window: window)
                Spacer(minLength: 0)
                ChromeButton(.sidebar, help: "Collapse sidebar") {
                    window.sidebarCollapsed = true
                }
            }
            .padding(.horizontal, 9)
            .frame(height: AetherMetrics.chromeHeight)

            if window.workspace.preferences.showFavorites {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42, maximum: 48), spacing: 6)], spacing: 6) {
                    ForEach(window.workspace.shortcuts.prefix(7)) { item in
                        shortcutTile(item)
                    }
                    addShortcutTile
                }
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 12)
            }

            Button { _ = window.newTab() } label: {
                HStack(spacing: 8) {
                    BrowserIconView(icon: .plus, tint: theme.muted).iconSize(12)
                    Text("New Tab").font(AetherType.body(12)).foregroundStyle(theme.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(SidebarRowStyle(reduced: reduced))
            .padding(.horizontal, 7)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !window.tabs.filter(\.isPinned).isEmpty {
                        sectionHeader("Pinned")
                        ForEach(window.tabs.filter(\.isPinned)) { tab in
                            TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false,
                                        window: window, namespace: tabGlass)
                        }
                    }
                    sectionHeader("Tabs")
                    ForEach(window.tabs.filter { !$0.isPinned }) { tab in
                        TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false,
                                    window: window, namespace: tabGlass)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.top, 2)
                .padding(.bottom, 12)
            }
            .padding(.top, 6)

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                ChromeButton(.history, help: "History", selected: window.showsHistory) { window.showsHistory = true }
                ChromeButton(.bookmark, help: "Bookmarks", selected: window.showsBookmarks) { window.showsBookmarks = true }
                Spacer(minLength: 0)
                ChromeButton(.search, help: "Search tabs", selected: window.showsTabSearch) {
                    window.showsTabSearch.toggle()
                }
            }
            .padding(.horizontal, 9).padding(.bottom, 8)
        }
        .frame(width: window.workspace.preferences.sidebarWidth)
        .background { AetherChromeBackground(.sidebar) }
        .animation(AetherMotion.tab(reduced), value: window.tabs.map(\.id))
        .animation(AetherMotion.tab(reduced), value: window.selectedID)
        .sheet(isPresented: $addingShortcut) { ShortcutEditor(workspace: window.workspace, shortcut: nil) }
    }

    private func shortcutTile(_ item: BrowserShortcut) -> some View {
        Button { _ = window.newTab(url: item.url) } label: {
            DomainIcon(item.url, size: 26)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(SidebarTileStyle(reduced: reduced))
        .help(item.name)
    }

    private var addShortcutTile: some View {
        Button { addingShortcut = true } label: {
            BrowserIconView(icon: .plus, tint: theme.soft).iconSize(13)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.soft.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
        }
        .buttonStyle(.plain)
        .help("Add shortcut")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(AetherType.sectionHeader(10))
            .tracking(0.4)
            .foregroundStyle(theme.soft)
            .padding(.horizontal, 9)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

struct SidebarRowStyle: ButtonStyle {
    @Environment(\.aetherTheme) private var theme
    let reduced: Bool
    var radius: CGFloat = AetherMetrics.fieldRadius
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { AetherFocusedFill(radius: radius) }
            .focusEffectDisabled()
            .modifier(AetherPointingCursor())
            .background(configuration.isPressed ? theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
    }
}

struct SidebarTileStyle: ButtonStyle {
    @Environment(\.aetherTheme) private var theme
    let reduced: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { AetherFocusedFill(radius: 8) }
            .focusEffectDisabled()
            .modifier(AetherPointingCursor())
            .background(configuration.isPressed ? theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
    }
}
