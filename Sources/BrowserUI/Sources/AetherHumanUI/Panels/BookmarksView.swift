import SwiftUI

public struct BookmarksView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @BrowserState private var query = ""
    @BrowserState private var transferError: String?
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }
    private var results: [BrowserBookmark] {
        window.workspace.bookmarks(for: window.activeProfileID).filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.localizedCaseInsensitiveContains(query)
        }
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Bookmarks").font(AetherType.title(24))
                Spacer()
                Button("Import") {
                    do { if let items = try BookmarkTransfer.importBookmarks() {
                        window.workspace.importBookmarks(items, into: window.activeProfileID)
                    } } catch { transferError = error.localizedDescription }
                }
                Button("Export") {
                    do { _ = try BookmarkTransfer.export(window.workspace.bookmarks(for: window.activeProfileID),
                        profileName: window.workspace.name(for: window.activeProfileID)) }
                    catch { transferError = error.localizedDescription }
                }
                ChromeButton("xmark", help: "Close") { dismiss() }
            }
            if let transferError { Text(transferError).font(AetherType.body(11)).foregroundStyle(theme.error) }
            AetherField("Search bookmarks", text: $query, icon: "magnifyingglass")
            if results.isEmpty {
                AetherEmptyState(symbol: "book", heading: "No bookmarks", description: "Save pages from the address bar to see them here.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(results) { mark in
                            HStack(spacing: 12) {
                                DomainIcon(mark.url, size: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mark.title).font(AetherType.medium(12)).lineLimit(1)
                                    Text(mark.url).font(AetherType.body(11)).foregroundStyle(theme.muted).lineLimit(1)
                                }
                                Spacer()
                                ChromeButton("xmark", help: "Remove bookmark") { window.workspace.deleteBookmark(mark.id) }
                            }
                            .padding(10).background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle()).onTapGesture { window.navigateSelected(mark.url); dismiss() }
                        }
                    }
                }
            }
        }
        .padding(24).frame(width: 680, height: 560).background(theme.canvas)
    }
}
