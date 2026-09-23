import SwiftUI

public struct SidebarTabListView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.aetherIsFullscreen) private var fullscreen
    @Environment(\.aetherTrafficLeading) private var trafficLeading
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var addingShortcut = false
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ProfileSwitcherView(window: window)
                Spacer(minLength: 0)
            }
            .padding(.leading, fullscreen ? 12 : trafficLeading).padding(.trailing, 6)
            .frame(height: 40)

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
                    BrowserIconView(icon: .plus, tint: chrome?.icon ?? theme.ink)
                        .iconSize(13)
                        .frame(width: 15, height: 15)
                    Text("New Tab").font(AetherType.body(12)).foregroundStyle(chrome?.text ?? theme.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(SidebarRowStyle(reduced: reduced, radius: AetherMetrics.fieldRadius))
            .focusEffectDisabled()
            .padding(.horizontal, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !window.tabs.filter(\.isPinned).isEmpty {
                        sectionHeader("Pinned")
                        ForEach(window.tabs.filter(\.isPinned)) { tab in
                            TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false,
                                        window: window)
                        }
                    }
                    ForEach(window.tabs.filter { !$0.isPinned }) { tab in
                        TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false,
                                    window: window)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 2)
                .padding(.bottom, 12)
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
                ChromeButton(.history, help: "History", selected: window.showsHistory) {
                    window.closeMenus()
                    window.showsHistory.toggle()
                }
                ChromeButton(.bookmark, help: "Bookmarks", selected: window.showsBookmarks) {
                    window.closeMenus()
                    window.showsBookmarks.toggle()
                }
                Spacer(minLength: 8)
                ProfileIndicatorStrip(window: window)
                Spacer(minLength: 8)
                ChromeButton(.search, help: "Search tabs", selected: window.showsTabSearch) {
                    window.closeMenus()
                    window.showsTabSearch.toggle()
                }
            }
            .padding(.horizontal, 9).padding(.bottom, 12)
        }
        .frame(width: window.workspace.preferences.transientSidebarWidth ?? window.workspace.preferences.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background { AetherChromeBackground(.sidebar) }
        .animation(AetherMotion.tab(reduced), value: window.tabs.map(\.id))
        .animation(AetherMotion.selection(reduced), value: window.selectedID)
        .sheet(isPresented: $addingShortcut) { ShortcutEditor(workspace: window.workspace, shortcut: nil) }
    }

    private func shortcutTile(_ item: BrowserShortcut) -> some View {
        Button { _ = window.newTab(url: item.url) } label: {
            DomainIcon(item.url, size: 17)
                .frame(maxWidth: .infinity).frame(height: 41)
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
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.muted.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
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

// One bright active dot and muted inactive dots, centered in the sidebar footer.
struct ProfileIndicatorStrip: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    let window: BrowserWindowModel

    var body: some View {
        let ids = window.workspace.profiles.prefix(5).map(\.id)
        let active = ids.firstIndex(of: window.activeProfileID) ?? 0
        HStack(spacing: 3) {
            ForEach(Array(ids.enumerated()), id: \.offset) { index, _ in
                Circle()
                    .fill(index == active
                          ? (chrome?.text ?? theme.ink)
                          : (chrome?.secondary ?? theme.muted).opacity(0.45))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

struct SidebarRowStyle: ButtonStyle {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @State private var hovering = false
    let reduced: Bool
    var radius: CGFloat = AetherMetrics.fieldRadius
    func makeBody(configuration: Configuration) -> some View {
        let active = hovering || configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .background { AetherFocusedFill(radius: radius) }
            .focusEffectDisabled()
            .pointerStyle(.link)
            .background {
                shape.fill(.clear)
                    .glassEffect(.regular.tint(Color.black.opacity(active ? 0.24 : 0.14)), in: shape)
                    .glassEffectTransition(.materialize)
                    .opacity(active ? 1 : 0)
            }
            .onHover { hovering = $0 }
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
            .animation(AetherMotion.hover(reduced), value: hovering)
    }
}

struct SidebarTileStyle: ButtonStyle {
    @Environment(\.aetherTheme) private var theme
    @State private var hovering = false
    let reduced: Bool
    func makeBody(configuration: Configuration) -> some View {
        let active = hovering || configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        configuration.label
            .background { AetherFocusedFill(radius: 8) }
            .focusEffectDisabled()
            .pointerStyle(.link)
            .background {
                shape.fill(.clear)
                    .glassEffect(.regular.tint(Color.black.opacity(active ? 0.24 : 0.14)), in: shape)
                    .glassEffectTransition(.materialize)
                    .opacity(active ? 1 : 0)
            }
            .onHover { hovering = $0 }
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
            .animation(AetherMotion.hover(reduced), value: hovering)
    }
}
