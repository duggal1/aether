import SwiftUI

public struct TopTabStripView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var addingShortcut = false
    @Namespace private var tabGlass
    let window: BrowserWindowModel
    let showsChrome: Bool
    public init(window: BrowserWindowModel, showsChrome: Bool = true) {
        self.window = window
        self.showsChrome = showsChrome
    }

    public var body: some View {
        HStack(spacing: 0) {
                HStack(spacing: 7) {
                    ProfileSwitcherView(window: window)
                        .padding(.leading, 10)
                    IncognitoToggleView(window: window)
                    let pinned = window.workspace.pinnedShortcuts()
                    if !pinned.isEmpty {
                        ForEach(pinned.prefix(6)) { item in
                            shortcutPill(item)
                        }
                    }
                    Button { addingShortcut = true } label: {
                        BrowserIconView(icon: .plus, tint: theme.soft).iconSize(11)
                            .frame(width: 21, height: 25)
                    }
                    .buttonStyle(.plain)
                    .aetherPointingCursor()
                    .focusEffectDisabled()
                    .help("Add shortcut")
                    .padding(.trailing, 9)
                }
            }
            .frame(width: AetherMetrics.profileClusterWidth, height: AetherMetrics.profileClusterHeight)
            .offset(y: -1)
            .zIndex(7)
            .padding(.trailing, 5)
            ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(window.tabs.enumerated()), id: \.element.id) { offset, tab in
                            TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false,
                                        window: window, topFused: true, isFirst: offset == 0, namespace: tabGlass)
                                .frame(width: AetherMetrics.tabWidth)
                        }
                        Button { _ = window.newTab() } label: {
                            BrowserIconView(icon: .plus, tint: theme.muted)
                                .iconSize(13)
                                .frame(width: 29, height: AetherMetrics.tabHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .aetherPointingCursor()
                        .focusEffectDisabled()
                        .help("New tab")
                        .padding(.leading, 4)
                        .offset(y: 1)
                    }
                    .padding(.top, 2)
                }
            }
            HStack(spacing: 9) {
                ChromeButton(.arrowDown, help: "Search tabs ⇧⌘A", selected: window.showsTabSearch) {
                    window.showsTabSearch.toggle()
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 2)
        }
        .padding(.leading, 84).padding(.trailing, 8)
        .frame(height: AetherMetrics.chromeHeight)
        .background { if showsChrome { AetherChromeBackground(.toolbar) } }
        .animation(AetherMotion.tab(reduced), value: window.tabs.map(\.id))
        .animation(AetherMotion.selection(reduced), value: window.selectedID)
        .sheet(isPresented: $addingShortcut) { ShortcutEditor(workspace: window.workspace, shortcut: nil) }
    }

    private func shortcutPill(_ item: BrowserShortcut) -> some View {
        Button { window.navigateSelected(item.url) } label: {
            DomainIcon(item.url, size: 16)
                .frame(width: 21, height: 25)
        }
        .buttonStyle(.plain)
        .aetherPointingCursor()
        .focusEffectDisabled()
        .help(item.name)
    }
}
