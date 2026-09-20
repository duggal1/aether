import SwiftUI

public struct TopTabStripView: View {
    @Environment(\.aetherTheme) private var theme
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }
    public var body: some View {
        HStack(spacing: 8) {
            ProfileSwitcherView(window: window)
            Rectangle().fill(theme.faintLine).frame(width: 1, height: 19)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(window.tabs.filter(\.isPinned)) { tab in
                        TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: true, window: window)
                    }
                    if !window.tabs.filter(\.isPinned).isEmpty {
                        Rectangle().fill(theme.faintLine).frame(width: 1, height: 18).padding(.horizontal, 5)
                    }
                    ForEach(window.tabs.filter { !$0.isPinned }) { tab in
                        TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false, window: window)
                            .frame(width: 164)
                    }
                }
            }
            AetherGlassGroup {
                HStack(spacing: 5) {
                    ChromeButton("plus", help: "New tab ⌘T") { _ = window.newTab() }
                    ChromeButton("chevron.down", help: "Search tabs", selected: window.showsTabSearch) {
                        window.showsTabSearch.toggle()
                    }
                }
            }
        }
        .padding(.horizontal, 11).frame(height: 43).background { AetherChromeBackground(.chrome) }
    }
}
