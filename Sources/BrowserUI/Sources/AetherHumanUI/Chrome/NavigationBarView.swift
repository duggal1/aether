import SwiftUI

public struct NavigationBarView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    let window: BrowserWindowModel
    let showsChrome: Bool
    public init(window: BrowserWindowModel, showsChrome: Bool = true) {
        self.window = window
        self.showsChrome = showsChrome
    }

    public var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                // No profile control here on purpose: the sidebar owns it in
                // sidebar arrangement, the tab strip owns it in top arrangement.
                // Rendering it twice is what made the window look redundant.
                if window.arrangement == .sidebar {
                    ChromeButton(.sidebar, help: window.sidebarCollapsed ? "Show sidebar" : "Hide sidebar") {
                        withAnimation(AetherMotion.sidebar(reduced)) {
                            window.sidebarCollapsed.toggle()
                        }
                    }
                    .padding(.leading, 4)
                }
                ChromeButton(.arrowLeft, help: "Back \u{2318}[", enabled: window.selected?.canGoBack == true, iconSize: 14) { window.perform(.back) }
                ChromeButton(.arrowRight, help: "Forward \u{2318}]", enabled: window.selected?.canGoForward == true, iconSize: 14) { window.perform(.forward) }
                ChromeButton(window.selected?.isLoading == true ? .close : .refresh,
                             help: window.selected?.isLoading == true ? "Stop loading" : "Reload \u{2318}R",
                             enabled: window.selected?.enginePageID != nil, iconSize: 14) {
                    window.perform(window.selected?.isLoading == true ? .stop : .reload)
                }
            }
            OmniboxView(window: window).padding(.horizontal, 7)
            HStack(spacing: 2) {
                AetherJevChip(window: window)
                AetherExtensionToolbarActions(window: window)
                ChromeButton(.search, help: "Search tabs, history, bookmarks \u{21E7}\u{2318}A",
                             selected: window.showsTabSearch, iconSize: 14) {
                    window.closeMenus()
                    window.showsTabSearch.toggle()
                }
                ChromeButton(.history, help: "History \u{2318}Y", selected: window.showsHistory, iconSize: 14) {
                    window.closeMenus()
                    window.toggleHistoryPanel()
                }
                ChromeButton(.moreHorizontal, help: "More browser actions", selected: window.showsMoreMenu, iconSize: 14) {
                    // One dropdown at a time: opening this closes the space menu
                    // and the extensions drawer rather than stacking on them.
                    if window.showsMoreMenu {
                        window.showsMoreMenu = false
                    } else {
                        window.closeMenus()
                        window.showsMoreMenu = true
                    }
                }
            }
        }
        .padding(.leading, window.arrangement == .sidebar && window.sidebarCollapsed ? 78 : 4)
        .padding(.trailing, 6)
        .frame(height: AetherMetrics.navigationHeight)
        .background { barSurface.allowsHitTesting(false) }
        .environment(\.colorScheme, chrome?.isDark ?? theme.dark ? .dark : .light)
    }

    // One chrome surface. The tab strip above and the address row here are two
    // tones of the same piece, and the active tab fills with this bar's tone, so
    // there is no junction for a seam, gap or hairline to appear in.
    private var barSurface: some View {
        AetherChromeBackground(.toolbar)
    }
}
