import SwiftUI

public struct MoreMenuView: View {
    @Environment(\.aetherTheme) private var theme
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }
    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuButton("Search Tabs", "magnifyingglass") { window.showsTabSearch = true }
            menuButton("History", "clock") { window.showsHistory = true }
            menuButton("Bookmarks", "book") { window.showsBookmarks = true }
            menuButton("Downloads", "arrow.down.circle") { window.showsDownloads = true }
            divider
            menuButton("Find in Page", "text.magnifyingglass") { window.showsFind = true }
            menuButton("Reader", "text.book.closed") { window.showsReader = true }
            menuButton("Inspect Page", "curlybraces") { window.showsInspector = true }
            divider
            menuButton(window.arrangement == .top ? "Use Sidebar Tabs" : "Use Top Tabs", "rectangle.split.2x1") {
                window.toggleArrangement()
            }
            SettingsLink {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape").frame(width: 15)
                    Text("Settings")
                    Spacer()
                }.font(AetherType.body(12)).foregroundStyle(theme.ink).padding(9)
            }.buttonStyle(.plain)
        }
        .padding(9).frame(width: 225).background { AetherPopoverBackground() }
    }
    private var divider: some View {
        Rectangle().fill(theme.faintLine).frame(height: 1).padding(.vertical, 5)
    }
    private func menuButton(_ name: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 15)
                Text(name)
                Spacer()
            }
            .font(AetherType.body(12)).foregroundStyle(theme.ink).padding(9)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
