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
            }
            .padding(.leading, 76).padding(.trailing, 6)
            .frame(height: 48)

            if window.workspace.preferences.showFavorites {
                let pinned = window.workspace.pinnedShortcuts()
                if !pinned.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(pinned.prefix(7)) { item in
                            shortcutTile(item)
                        }
                        addShortcutTile
                    }
                    .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 12)
                }
            }

            Button { _ = window.newTab() } label: {
                HStack(spacing: 9) {
                    BrowserIconView(icon: .plus, tint: theme.muted).iconSize(14)
                        .offset(y: -0.5)
                    Text("New Tab").font(AetherType.emphasis(12)).foregroundStyle(theme.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 35)
                .contentShape(Rectangle())
            }
            .buttonStyle(SidebarRowStyle(reduced: reduced, radius: 7))
            .focusEffectDisabled()
            .padding(.horizontal, 6)

            ScrollView {
                AetherGlassCluster(spacing: 4) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !window.tabs.filter(\.isPinned).isEmpty {
                            sectionHeader("Pinned")
                            ForEach(window.tabs.filter(\.isPinned)) { tab in
                                TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false,
                                            window: window, namespace: tabGlass)
                            }
                        }
                        ForEach(window.tabs.filter { !$0.isPinned }) { tab in
                            TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false,
                                        window: window, namespace: tabGlass)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                    .padding(.bottom, 12)
                }
            }
            .scrollClipDisabled()
            .mask {
                if window.tabs.count > 9 {
                    LinearGradient(
                        stops: [.init(color: .black, location: 0),
                                .init(color: .black, location: 0.87),
                                .init(color: .clear, location: 1)],
                        startPoint: .top, endPoint: .bottom)
                } else {
                    Rectangle().fill(.black)
                }
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
            .padding(.horizontal, 9).padding(.bottom, 12)
        }
        .frame(width: window.workspace.preferences.transientSidebarWidth ?? window.workspace.preferences.sidebarWidth)
        .background { AetherChromeBackground(.sidebar) }
        .animation(AetherMotion.tab(reduced), value: window.tabs.map(\.id))
        .animation(AetherMotion.selection(reduced), value: window.selectedID)
        .sheet(isPresented: $addingShortcut) { ShortcutEditor(workspace: window.workspace, shortcut: nil) }
    }

    private func shortcutTile(_ item: BrowserShortcut) -> some View {
        Button { _ = window.newTab(url: item.url) } label: {
            DomainIcon(item.url, size: 17)
                .frame(maxWidth: .infinity).frame(height: 41)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.card)
                }
        }
        .buttonStyle(SidebarTileStyle(reduced: reduced))
        .focusEffectDisabled()
        .help(item.name)
        .contextMenu {
            Button("Open in New Tab") { _ = window.newTab(url: item.url) }
            Button(item.isPinned ? "Unpin" : "Pin") { window.workspace.toggleShortcutPin(item.id) }
        }
    }

    private var addShortcutTile: some View {
        Button { addingShortcut = true } label: {
            BrowserIconView(icon: .plus, tint: theme.soft).iconSize(13)
                .frame(maxWidth: .infinity).frame(height: 41)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
        }
        .buttonStyle(.plain)
        .aetherPointingCursor()
        .help("Add shortcut")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AetherType.sectionHeader(10))
            .foregroundStyle(theme.soft)
            .padding(.horizontal, 9)
            .padding(.top, 8)
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
            .pointerStyle(.link)
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
            .pointerStyle(.link)
            .background(configuration.isPressed ? theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
    }
}
