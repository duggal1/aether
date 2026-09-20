import SwiftUI

public struct SidebarTabListView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                ProfileSwitcherView(window: window)
                Spacer(minLength: 0)
                ChromeButton("sidebar.left", help: "Collapse sidebar") {
                    withAnimation(AetherMotion.sidebar(reduced)) { window.sidebarCollapsed = true }
                }
            }
            .padding(.horizontal, 10).frame(height: 45)
            if window.workspace.preferences.showFavorites {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 50), spacing: 7)], spacing: 7) {
                    ForEach(window.workspace.shortcuts.prefix(8)) { item in
                        Button { _ = window.newTab(url: item.url) } label: {
                            DomainIcon(item.url, size: 22).frame(maxWidth: .infinity).frame(height: 39)
                                .background(theme.subtle, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain).help(item.name)
                    }
                }.padding(.horizontal, 11).padding(.top, 12).padding(.bottom, 17)
            }
            Button { _ = window.newTab() } label: {
                Label("New Tab", systemImage: "plus")
                    .font(AetherType.medium(12)).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(theme.muted).padding(.horizontal, 11).frame(height: 34)
            }.buttonStyle(.plain).padding(.horizontal, 8)
            Rectangle().fill(theme.faintLine).frame(height: 1).padding(.horizontal, 14).padding(.vertical, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(window.tabs.filter(\.isPinned)) { tab in
                        TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false, window: window)
                    }
                    if !window.tabs.filter(\.isPinned).isEmpty {
                        Text("TABS").font(AetherType.medium(10)).foregroundStyle(theme.soft)
                            .padding(.horizontal, 11).padding(.top, 12).padding(.bottom, 4)
                    }
                    ForEach(window.tabs.filter { !$0.isPinned }) { tab in
                        TabItemView(tab: tab, selected: window.selectedID == tab.id, compact: false, window: window)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
            Spacer(minLength: 0)
            HStack {
                ChromeButton("clock.arrow.circlepath", help: "History") { window.showsHistory = true }
                ChromeButton("book", help: "Bookmarks") { window.showsBookmarks = true }
                Spacer()
                ChromeButton("magnifyingglass", help: "Search tabs") { window.showsTabSearch.toggle() }
            }
            .padding(.horizontal, 9).padding(.bottom, 9)
        }
        .frame(width: window.workspace.preferences.sidebarWidth)
        .background { AetherChromeBackground(.sidebar) }
        .overlay(alignment: .trailing) { Rectangle().fill(theme.faintLine).frame(width: 1) }
    }
}
