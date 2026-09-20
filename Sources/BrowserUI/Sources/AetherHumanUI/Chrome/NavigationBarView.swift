import SwiftUI

public struct NavigationBarView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var showsMore = false
    let window: BrowserWindowModel
    let showsChrome: Bool
    public init(window: BrowserWindowModel, showsChrome: Bool = true) {
        self.window = window
        self.showsChrome = showsChrome
    }

    public var body: some View {
        HStack(spacing: 4) {
            if window.arrangement == .sidebar && window.sidebarCollapsed {
                ChromeButton(.sidebar, help: "Show sidebar") {
                    window.sidebarCollapsed = false
                }
            }
            ChromeButton(.arrowLeft, help: "Back \u{2318}[", enabled: window.selected?.canGoBack == true) { window.perform(.back) }
            ChromeButton(.arrowRight, help: "Forward \u{2318}]", enabled: window.selected?.canGoForward == true) { window.perform(.forward) }
            ChromeButton(window.selected?.loadState == .loading ? .close : .refresh,
                         help: window.selected?.loadState == .loading ? "Stop loading" : "Reload \u{2318}R",
                         enabled: window.selected?.enginePageID != nil) {
                window.perform(window.selected?.loadState == .loading ? .stop : .reload)
            }
            OmniboxView(window: window).padding(.horizontal, 7)
            HStack(spacing: 2) {
                ChromeButton(.search, help: "Search tabs, history, bookmarks \u{21E7}\u{2318}A",
                             selected: window.showsTabSearch) { window.showsTabSearch.toggle() }
                ChromeButton(.history, help: "History \u{2318}Y", selected: window.showsHistory) {
                    window.showsHistory.toggle()
                }
                ChromeButton(.download, help: "Downloads", selected: window.showsDownloads) {
                    window.showsDownloads.toggle()
                }
                ChromeButton(.moreHorizontal, help: "More browser actions", selected: showsMore) {
                    showsMore.toggle()
                }
                .popover(isPresented: $showsMore) { MoreMenuView(window: window) }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: AetherMetrics.chromeHeight)
        .background { if showsChrome { AetherChromeBackground(.toolbar) } }
    }
}
