import SwiftUI

public struct TopTabStripView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.aetherIsFullscreen) private var fullscreen
    @Environment(\.aetherTrafficLeading) private var trafficLeading
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var newTabHovering = false

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
                AetherExtensionsButton(window: window)
                IncognitoToggleView(window: window)
            }
            .frame(height: AetherMetrics.profileClusterHeight)
            .zIndex(7)
            .padding(.trailing, 4)
            GeometryReader { proxy in
                let layout = tabLayout(available: proxy.size.width)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        let pinned = window.workspace.pinnedShortcuts()
                        if !pinned.isEmpty {
                            ForEach(pinned.prefix(6)) { item in
                                shortcutPill(item)
                            }
                        }
                        ForEach(Array(window.tabs.enumerated()), id: \.element.id) { offset, tab in
                            TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: layout.compact,
                                        window: window, topFused: true, isFirst: offset == 0)
                                .frame(width: layout.tabWidth)
                        }
                        Button { _ = window.newTab() } label: {
                            BrowserIconView(icon: .plus,
                                            tint: newTabHovering ? (chrome?.text ?? theme.ink)
                                                                 : (chrome?.icon ?? theme.muted))
                                .iconSize(14)
                                .frame(width: 29, height: AetherMetrics.tabHeight)
                                .background { AetherInteractionSurface(active: newTabHovering, radius: AetherMetrics.utilityRadius) }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .aetherPointingCursor()
                        .focusEffectDisabled()
                        .help("New tab")
                        .padding(.leading, 4)
                        .animation(AetherMotion.hover(reduced), value: newTabHovering)
                        .onHover { newTabHovering = $0 }
                    }
                    .padding(.top, 2)
                }
                .animation(AetherMotion.tab(reduced), value: layout.key)
            }
            .frame(height: AetherMetrics.chromeHeight)
            HStack(spacing: 9) {
                ChromeButton(.arrowDown, help: "Search tabs ⇧⌘A", selected: window.showsTabSearch) {
                    window.showsTabSearch.toggle()
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 2)
        }
        .padding(.leading, fullscreen ? 12 : trafficLeading + 2).padding(.trailing, 8)
        .frame(height: AetherMetrics.chromeHeight)
        .background {
            if showsChrome { AetherChromeBackground(.tabStrip) }
        }
        .animation(AetherMotion.tab(reduced), value: window.tabs.map(\.id))
        .animation(AetherMotion.selection(reduced), value: window.selectedID)
    }

    private struct TopTabLayout {
        let tabWidth: CGFloat
        let compact: Bool
        let key: String
    }

    private func tabLayout(available: CGFloat) -> TopTabLayout {
        let pills = CGFloat(min(6, window.workspace.pinnedShortcuts().count)) * 21
        let reserve = pills + 33 + 8
        let count = max(window.tabs.count, 1)
        let width = min(AetherMetrics.tabWidth, max(46, (available - reserve) / CGFloat(count)))
        return TopTabLayout(tabWidth: width, compact: width < 108,
                            key: "\(window.tabs.count)|\(Int(available))")
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
