import SwiftUI

public struct BookmarksView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @BrowserState private var query = ""
    @BrowserState private var transferError: String?
    @State private var closeHovering = false
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var results: [BrowserBookmark] {
        window.workspace.bookmarks(for: window.activeProfileID)
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
                || $0.url.localizedCaseInsensitiveContains(query) }
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
        VStack(alignment: .leading, spacing: 19) {
            HStack(spacing: 9) {
                Text("Bookmarks")
                    .font(AetherType.panelTitle(22)).tracking(AetherTracking.heading)
                    .foregroundStyle(theme.textStrong)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Button("Import") {
                        do {
                            if let items = try BookmarkTransfer.importBookmarks() {
                                window.workspace.importBookmarks(items, into: window.activeProfileID)
                            }
                        } catch { transferError = error.localizedDescription }
                    }
                    .aetherProminentButton()
                    .frame(minWidth: 88, minHeight: 30)
                    Button("Export") {
                        do {
                            _ = try BookmarkTransfer.export(window.workspace.bookmarks(for: window.activeProfileID),
                                profileName: window.workspace.name(for: window.activeProfileID))
                        } catch { transferError = error.localizedDescription }
                    }
                    .aetherButton()
                    .frame(minWidth: 88, minHeight: 30)
                }
                Button { window.showsBookmarks = false } label: {
                    Image(systemName: "xmark")
                        .font(AetherType.symbol(11))
                        .foregroundStyle(theme.muted)
                        .frame(width: 28, height: 28)
                        .background { AetherInteractionSurface(active: closeHovering, radius: 6) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .aetherPointingCursor()
                .onHover { closeHovering = $0 }
                .help("Close bookmarks")
            }

            AetherField("Search bookmarks", text: $query, icon: .search)
            if let transferError {
                Text(transferError).font(AetherType.caption(12)).foregroundStyle(theme.error)
            }

            if results.isEmpty {
                AetherEmptyState(icon: .bookmark, heading: "No bookmarks",
                                 description: "Save pages from the address bar to see them here.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(folders, id: \.name) { folder in
                            BookmarkFolderSection(
                                folder: folder.name, marks: folder.marks,
                                open: { mark in
                                    window.navigateSelected(mark.url)
                                    window.showsBookmarks = false
                                },
                                delete: { id in window.workspace.deleteBookmark(id) })
                        }
                    }
                    .padding(.bottom, 22)
                }
                .background { AetherOverlayScrollerTuning() }
                .mask {
                    if results.count > 7 {
                        LinearGradient(
                            stops: [.init(color: .black, location: 0),
                                    .init(color: .black, location: 0.82),
                                    .init(color: .black.opacity(0.6), location: 0.92),
                                    .init(color: .clear, location: 1)],
                            startPoint: .top, endPoint: .bottom)
                    } else {
                        Rectangle().fill(.black)
                    }
                }
            }
        }
        .padding(26)
        .frame(width: 720, height: 555)
        .background { AetherOverlayPanelBackground() }
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.panelRadius, style: .continuous))
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
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(AetherMotion.popover(reduced)) { expanded.toggle() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "folder")
                        .font(AetherType.symbol(16))
                        .foregroundStyle(AetherPalette.folderColor)
                        .frame(width: 19)
                    Text(folder)
                        .font(AetherType.emphasis(13))
                        .foregroundStyle(theme.textStrong)
                    Text("\(marks.count)")
                        .font(AetherType.caption(12))
                        .foregroundStyle(theme.muted)
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(AetherType.symbol(12))
                        .foregroundStyle(theme.muted)
                }
                .padding(.horizontal, 11)
                .frame(height: 37)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .aetherPointingCursor()
            .focusEffectDisabled()
            if expanded {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(marks) { mark in
                        BookmarkEntry(mark: mark, open: { open(mark) }, delete: { delete(mark.id) })
                    }
                }
                .transition(AetherMotion.disclosure(reduced, expanded: expanded))
            }
        }
    }
}

private struct BookmarkEntry: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovering = false
    @FocusState private var deleteFocused: Bool
    let mark: BrowserBookmark
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 12) {
                    DomainIcon(mark.url, size: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mark.title).font(AetherType.emphasis(13))
                            .foregroundStyle(theme.textStrong).lineLimit(1)
                        Text(mark.url).font(AetherType.caption(11))
                            .foregroundStyle(theme.muted).lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(AetherType.symbol(12))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .aetherPointingCursor()
            .focusEffectDisabled()
            Button(action: delete) {
                Image(systemName: "xmark")
                    .font(AetherType.symbol(12))
                    .foregroundStyle(theme.muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .aetherPointingCursor()
            .focused($deleteFocused)
            .help("Remove bookmark")
            .opacity(hovering || deleteFocused ? 1 : 0)
            .allowsHitTesting(hovering || deleteFocused)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(hovering ? theme.hover : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .animation(AetherMotion.hover(reduced), value: hovering)
        .onHover { hovering = $0 }
    }
}
