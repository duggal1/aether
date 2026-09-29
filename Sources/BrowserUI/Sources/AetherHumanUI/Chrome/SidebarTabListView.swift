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
                AetherExtensionsButton(window: window)
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

            Button { withAnimation(AetherMotion.tab(reduced)) { _ = window.newTab() } } label: {
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

            // One deliberately composed action row: actions on the left, the
            // space indicator centred in the space that is left, search on the
            // right. The dots are laid out in the row, not positioned by
            // coordinates, so they share the icons' baseline.
            HStack(spacing: 2) {
                ChromeButton(.history, help: "History", selected: window.showsHistory) {
                    window.closeMenus()
                    window.toggleHistoryPanel()
                }
                ChromeButton(.bookmark, help: "Bookmarks", selected: window.showsBookmarks) {
                    window.closeMenus()
                    window.toggleBookmarksPanel()
                }
                Spacer(minLength: 6)
                profileDots
                Spacer(minLength: 6)
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
        // Deliberately no `animation(_:value:)` over the tab list. It fired for
        // every reorder and every pin as well as every close, and it wrapped
        // each close in an animated relayout of every row in the sidebar — the
        // more tabs there were, the longer a close took. Each tab animation is
        // now raised by the action that causes it, so a close animates a close.
        .animation(AetherMotion.selection(reduced), value: window.selectedID)
        .sheet(isPresented: $addingShortcut) { AetherDialogScope { ShortcutEditor(workspace: window.workspace, shortcut: nil) } }
    }

    /// One dot per space, living in the sidebar's action row. The active space
    /// is the solid dot; the rest are faded. They are a state readout first and
    /// a control second, so they stay tiny, monochrome and label-free.
    ///
    /// The tone inverts with the sidebar: the dot is white on a dark sidebar and
    /// near-black on the light one, because a white dot on the light veil — or a
    /// black one on the charcoal — is simply not there. The faded step keeps the
    /// off-white/neutral ratio the design calls for.
    @ViewBuilder private var profileDots: some View {
        let profiles = window.workspace.profiles
        if profiles.count > 1 {
            HStack(spacing: 1) {
                ForEach(profiles) { profile in
                    let active = profile.id == window.activeProfileID
                    Button {
                        window.switchProfile(profile.id)
                    } label: {
                        Circle()
                            .fill(dotInk(active: active))
                            .frame(width: 6, height: 6)
                            .frame(width: 14, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .aetherPointingCursor()
                    .help(profile.name)
                    .accessibilityLabel("Space: \(profile.name)")
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .animation(AetherMotion.selection(reduced), value: active)
                }
            }
        }
    }

    private func dotInk(active: Bool) -> Color {
        let dark = chrome?.isDark ?? theme.dark
        if dark { return active ? Color.white : Color(white: 0.64) }
        return active ? Color(white: 0.10) : Color(white: 0.60)
    }

    private func shortcutTile(_ item: BrowserShortcut) -> some View {
        Button { withAnimation(AetherMotion.tab(reduced)) { _ = window.newTab(url: item.url) } } label: {
            DomainIcon(item.url, size: 17)
                .frame(maxWidth: .infinity).frame(height: 41)
        }
        .buttonStyle(SidebarTileStyle(reduced: reduced))
        .focusEffectDisabled()
        .help(item.name)
        .contextMenu {
            Button("Open in New Tab") { withAnimation(AetherMotion.tab(reduced)) { _ = window.newTab(url: item.url) } }
            Button(item.isPinned ? "Unpin" : "Pin") { withAnimation(AetherMotion.tab(reduced)) { window.workspace.toggleShortcutPin(item.id) } }
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
                shape.fill(chrome?.sidebarHover ?? (theme.dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)))
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
    @Environment(\.aetherChromeAppearance) private var chrome
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
                shape.fill(chrome?.sidebarHover ?? (theme.dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)))
                    .opacity(active ? 1 : 0)
            }
            .onHover { hovering = $0 }
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
            .animation(AetherMotion.hover(reduced), value: hovering)
    }
}
