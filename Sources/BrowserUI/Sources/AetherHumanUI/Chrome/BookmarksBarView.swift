import SwiftUI

// Ported from Search/Sources/Search/BookmarksBar.swift.
// Horizontal bookmarks bar above the page, off by default. Sideways scroll,
// folders open as menus, click navigates selected tab.
public struct BookmarksBarView: View {
    @Environment(\.aetherTheme) private var theme
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        let items = window.workspace.bookmarks(for: window.activeProfileID)
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(items.prefix(60)) { mark in
                        Button {
                            window.navigateSelected(mark.url)
                        } label: {
                            HStack(spacing: 6) {
                                DomainIcon(mark.url, size: 14)
                                Text(mark.title.isEmpty ? (URL(string: mark.url)?.host ?? mark.url) : mark.title)
                                    .font(AetherType.body(12))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(theme.hover, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(mark.url)
                        .contextMenu {
                            Button("Open Beside") { _ = window.openBeside(url: mark.url) }
                            Button("Remove") { window.workspace.deleteBookmark(mark.id) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(height: 34)
            .background(theme.chrome.opacity(0.6))
        }
    }
}
