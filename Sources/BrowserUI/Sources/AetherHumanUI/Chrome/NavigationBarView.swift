import SwiftUI

public struct NavigationBarView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
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
            HStack(spacing: 4) {
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
                ChromeButton(.search, help: "Search tabs, history, bookmarks \u{21E7}\u{2318}A",
                             selected: window.showsTabSearch, iconSize: 14) { window.showsTabSearch.toggle() }
                ChromeButton(.history, help: "History \u{2318}Y", selected: window.showsHistory, iconSize: 14) {
                    window.showsHistory.toggle()
                }
                ChromeButton(.moreHorizontal, help: "More browser actions", selected: showsMore, iconSize: 14) {
                    showsMore.toggle()
                }
                .popover(isPresented: $showsMore, arrowEdge: .bottom) {
                    MoreMenuView(window: window)
                        .presentationBackground(.clear)
                        .preferredColorScheme(chrome?.isDark ?? theme.dark ? .dark : .light)
                        .environment(\.aetherChromeAppearance, chrome ?? (theme.dark ? .dark : .light))
                }
            }
        }
        .padding(.leading, window.arrangement == .sidebar && window.sidebarCollapsed ? 78 : 4)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background { barSurface.allowsHitTesting(false) }
        .environment(\.colorScheme, chrome?.isDark ?? theme.dark ? .dark : .light)
    }

    // Dia geometry: in top-tabs mode the strip, the active tab, and this bar
    // are one continuous address-input surface. In sidebar mode the bar keeps
    // the general toolbar surface with a distinct address pill.
    private var barSurface: some View {
        Group {
            if window.arrangement == .top {
                chrome?.addressBG ?? theme.omnibox
            } else {
                AetherChromeBackground(.toolbar)
            }
        }
    }
}
