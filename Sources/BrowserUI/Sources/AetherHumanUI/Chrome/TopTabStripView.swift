import SwiftUI

public struct TopTabStripView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Namespace private var tabGlass
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        HStack(spacing: 9) {
            ProfileSwitcherView(window: window)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(window.tabs.filter(\.isPinned)) { tab in
                        TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: true,
                                    window: window, namespace: tabGlass)
                    }
                    ForEach(window.tabs.filter { !$0.isPinned }) { tab in
                        TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false,
                                    window: window, namespace: tabGlass)
                            .frame(width: 168)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack(spacing: 2) {
                ChromeButton(.plus, help: "New tab \u{2318}T") { _ = window.newTab() }
                ChromeButton(.arrowDown, help: "Tab list", selected: window.showsTabSearch) {
                    window.showsTabSearch.toggle()
                }
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 43)
        .background { AetherChromeBackground(.chrome) }
        .animation(AetherMotion.tab(reduced), value: window.tabs.map(\.id))
        .animation(AetherMotion.tab(reduced), value: window.selectedID)
    }
}
