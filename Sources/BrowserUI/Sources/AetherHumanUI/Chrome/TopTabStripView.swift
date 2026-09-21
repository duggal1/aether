import SwiftUI

public struct TopTabStripView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Namespace private var tabGlass
    let window: BrowserWindowModel
    let showsChrome: Bool
    public init(window: BrowserWindowModel, showsChrome: Bool = true) {
        self.window = window
        self.showsChrome = showsChrome
    }

    public var body: some View {
        HStack(spacing: 5.5) {
            HStack(spacing: 0) {
                ProfileSwitcherView(window: window)
                    .padding(.leading, 10)
                ForEach(window.workspace.shortcuts.prefix(6)) { item in
                    Button { window.navigateSelected(item.url) } label: {
                        DomainIcon(item.url, size: 16)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(AetherPressStyle(reduced: reduced))
                    .help(item.name)
                }
            }
            .frame(height: 32)
            .padding(.trailing, 8)
            .background { pillBackground }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5.5) {
                    ForEach(window.tabs) { tab in
                        TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false,
                                    window: window, topFused: true, namespace: tabGlass)
                            .frame(width: 171)
                    }
                    ChromeButton(.plus, help: "New tab ⌘T") { _ = window.newTab() }
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 15)
                .padding(.top, 3)
            }
            HStack(spacing: 2) {
                ChromeButton(.arrowDown, help: "Search tabs ⇧⌘A", selected: window.showsTabSearch) {
                    window.showsTabSearch.toggle()
                }
            }
        }
        .padding(.leading, 84).padding(.trailing, 8)
        .frame(height: 42)
        .background { if showsChrome { AetherChromeBackground(.toolbar) } }
        .animation(AetherMotion.tab(reduced), value: window.tabs.map(\.id))
        .animation(AetherMotion.selection(reduced), value: window.selectedID)
    }

    private var pillBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AetherPalette.tile(theme.dark).opacity(0.8))
    }
}
