import SwiftUI

public struct NavigationBarView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var showsMore = false
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }
    public var body: some View {
        HStack(spacing: 3) {
            if window.arrangement == .sidebar && window.sidebarCollapsed {
                ChromeButton("sidebar.left", help: "Show sidebar") {
                    withAnimation(AetherMotion.sidebar(reduced)) { window.sidebarCollapsed = false }
                }
            }
            ChromeButton("chevron.left", help: "Back ⌘[", enabled: window.selected?.canGoBack == true) { window.perform(.back) }
            ChromeButton("chevron.right", help: "Forward ⌘]", enabled: window.selected?.canGoForward == true) { window.perform(.forward) }
            ChromeButton(window.selected?.loadState == .loading ? "xmark" : "arrow.clockwise",
                         help: window.selected?.loadState == .loading ? "Stop loading" : "Reload ⌘R",
                         enabled: window.selected?.enginePageID != nil) {
                window.perform(window.selected?.loadState == .loading ? .stop : .reload)
            }
            OmniboxView(window: window).padding(.horizontal, 9)
            AetherGlassGroup {
                HStack(spacing: 4) {
                    ChromeButton("clock.arrow.circlepath", help: "History", selected: window.showsHistory) { window.showsHistory.toggle() }
                    ChromeButton("arrow.down.circle", help: "Downloads", selected: window.showsDownloads) { window.showsDownloads.toggle() }
                    ChromeButton("ellipsis", help: "More browser actions", selected: showsMore) { showsMore.toggle() }
                        .popover(isPresented: $showsMore) { MoreMenuView(window: window) }
                        .popover(isPresented: Binding(get: { window.showsTabSearch }, set: { window.showsTabSearch = $0 })) {
                            TabSearchView(window: window)
                        }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: AetherMetrics.chromeHeight)
        .background { AetherChromeBackground(.chrome) }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.faintLine).frame(height: 1) }
    }
}
