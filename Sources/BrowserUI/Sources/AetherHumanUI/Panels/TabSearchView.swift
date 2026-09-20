import SwiftUI

public struct TabSearchView: View {
    @Environment(\.aetherTheme) private var theme
    @BrowserState private var query = ""
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }
    private var matches: [BrowserTab] {
        window.tabs.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.url?.localizedCaseInsensitiveContains(query) == true) }
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AetherField("Search tabs, history, bookmarks", text: $query, icon: "magnifyingglass")
            groupHeader("OPEN TABS")
            if matches.isEmpty { caption("No matching tabs") }
            ForEach(matches) { tab in
                Button {
                    window.select(tab.id)
                    window.showsTabSearch = false
                } label: {
                    HStack(spacing: 10) {
                        DomainIcon(tab.url)
                        Text(tab.title).font(AetherType.body(12)).lineLimit(1)
                        Spacer()
                        if tab.id == window.selectedID {
                            Image(systemName: "checkmark").font(.system(size: 11)).foregroundStyle(theme.muted)
                        }
                    }.foregroundStyle(theme.ink).padding(9)
                }.buttonStyle(.plain)
            }
            if !window.closedTabs.filter({ $0.profileID == window.activeProfileID }).isEmpty {
                groupHeader("RECENTLY CLOSED")
                ForEach(window.closedTabs.filter { $0.profileID == window.activeProfileID }.prefix(5)) { tab in
                    Button { window.restoreClosed(tab.id); window.showsTabSearch = false } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath").frame(width: 16)
                            Text(tab.title).lineLimit(1)
                            Spacer()
                        }.foregroundStyle(theme.ink).font(AetherType.body(12)).padding(9)
                    }.buttonStyle(.plain)
                }
            }
            Rectangle().fill(theme.faintLine).frame(height: 1)
            Button { window.showsTabSearch = false; window.showsHistory = true } label: { footer("clock", "History") }
            Button { window.showsTabSearch = false; window.showsBookmarks = true } label: { footer("book", "Bookmarks") }
        }
        .buttonStyle(.plain)
        .padding(12)
        .frame(width: 350)
        .background { AetherPopoverBackground() }
    }
    private func groupHeader(_ title: String) -> some View {
        Text(title).font(AetherType.medium(10)).foregroundStyle(theme.soft)
            .padding(.leading, 9).padding(.top, 5)
    }
    private func caption(_ message: String) -> some View {
        Text(message).font(AetherType.body(12)).foregroundStyle(theme.muted).padding(12)
    }
    private func footer(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 16)
            Text(title); Spacer(); Image(systemName: "chevron.right").font(.system(size: 10))
        }.font(AetherType.body(12)).foregroundStyle(theme.ink).padding(9)
    }
}
