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
        HStack(spacing: 6) {
            ProfileSwitcherView(window: window)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(window.tabs.filter(\.isPinned)) { tab in
                        TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: true,
                                    window: window, namespace: tabGlass)
                    }
                    ForEach(window.tabs.filter { !$0.isPinned }) { tab in
                        TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false,
                                    window: window, namespace: tabGlass)
                            .frame(width: 156)
                    }
                }
                .padding(.vertical, 2)
            }
            HStack(spacing: 2) {
                ChromeButton(.plus, help: "New tab \u{2318}T") { _ = window.newTab() }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background { if showsChrome { AetherChromeBackground(.toolbar) } }
        .animation(AetherMotion.tab(reduced), value: window.tabs.map(\.id))
        .animation(AetherMotion.selection(reduced), value: window.selectedID)
    }
}
