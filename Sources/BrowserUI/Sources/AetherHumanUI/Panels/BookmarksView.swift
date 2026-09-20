import SwiftUI

public struct BookmarksView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @BrowserState private var query = ""
    @BrowserState private var transferError: String?
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var results: [BrowserBookmark] {
        window.workspace.bookmarks(for: window.activeProfileID)
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.url.localizedCaseInsensitiveContains(query) }
    }

    private var folders: [(name: String, marks: [BrowserBookmark])] {
        var order: [String] = []
        var buckets: [String: [BrowserBookmark]] = [:]
        for mark in results {
            let name = mark.folder.isEmpty ? "Favorites" : mark.folder
            if buckets[name] == nil { order.append(name) }
            buckets[name, default: []].append(mark)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("Bookmarks").font(AetherType.panelTitle(20)).foregroundStyle(theme.heading)
                Spacer(minLength: 8)
                Button("Import") {
                    do {
                        if let items = try BookmarkTransfer.importBookmarks() {
                            window.workspace.importBookmarks(items, into: window.activeProfileID)
                        }
                    } catch { transferError = error.localizedDescription }
                }
                .aetherButtonStyle()
                Button("Export") {
                    do {
                        _ = try BookmarkTransfer.export(window.workspace.bookmarks(for: window.activeProfileID),
                            profileName: window.workspace.name(for: window.activeProfileID))
                    } catch { transferError = error.localizedDescription }
                }
                .aetherButtonStyle()
                ChromeButton(.close, help: "Close") { dismiss() }
            }
            if let transferError {
                Text(transferError).font(AetherType.caption(11)).foregroundStyle(theme.error)
            }
            AetherField("Search bookmarks", text: $query, icon: .search)
            if results.isEmpty {
                AetherEmptyState(icon: .bookmark, heading: "No bookmarks",
                                 description: "Save pages from the address bar to see them here.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(folders, id: \.name) { folder in
                            BookmarkFolderSection(folder: folder.name, marks: folder.marks, open: { mark in
                                window.navigateSelected(mark.url)
                                dismiss()
                            }, delete: { id in
                                window.workspace.deleteBookmark(id)
                            })
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 680, height: 560)
        .background(theme.raised)
    }
}

private struct BookmarkFolderSection: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var expanded = true
    let folder: String
    let marks: [BrowserBookmark]
    let open: (BrowserBookmark) -> Void
    let delete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { withAnimation(AetherMotion.popover(reduced)) { expanded.toggle() } } label: {
                HStack(spacing: 10) {
                    AetherSymbolView(.folder, tint: theme.muted, size: 13)
                    Text(folder).font(AetherType.rowTitle(12.5)).foregroundStyle(theme.ink)
                    Text("\(marks.count)").font(AetherType.caption(11)).foregroundStyle(theme.soft)
                    Spacer(minLength: 6)
                    AetherSymbolView(expanded ? .discloseDown : .forward, tint: theme.soft, size: 10)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(AetherPressStyle(reduced: reduced))
            if expanded {
                ForEach(marks) { mark in
                    HoverSurface(radius: 8) {
                        HStack(spacing: 12) {
                            DomainIcon(mark.url, size: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mark.title).font(AetherType.rowTitle(12)).lineLimit(1)
                                Text(mark.url).font(AetherType.caption(11)).foregroundStyle(theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            AetherSymbolView(.forward, tint: theme.soft, size: 10)
                            ChromeButton(.close, help: "Remove bookmark", size: 24) {
                                delete(mark.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .contentShape(Rectangle())
                    }
                    .onTapGesture { open(mark) }
                }
            }
        }
    }
}
