import SwiftUI

public struct OmniboxView: View {
    @Environment(\.aetherTheme) private var theme
    @FocusState private var focused: Bool
    @BrowserState private var draft = ""
    @BrowserState private var selection = 0
    @BrowserState private var showingSuggestions = false
    let window: BrowserWindowModel

    public init(window: BrowserWindowModel) { self.window = window }
    private var matches: [OmniboxResult] {
        let query = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var items: [OmniboxResult] = []
        for tab in window.tabs where tab.title.localizedCaseInsensitiveContains(query) || (tab.url?.localizedCaseInsensitiveContains(query) == true) {
            items.append(OmniboxResult(id: tab.id, title: tab.title, subtitle: tab.url ?? "", kind: .tab, url: tab.url))
        }
        for item in window.workspace.bookmarks(for: window.activeProfileID) where item.title.localizedCaseInsensitiveContains(query) || item.url.localizedCaseInsensitiveContains(query) {
            items.append(OmniboxResult(id: item.id, title: item.title, subtitle: item.url, kind: .bookmark, url: item.url))
        }
        for item in window.workspace.visits where item.profileID == window.activeProfileID && (item.title.localizedCaseInsensitiveContains(query) || item.url.localizedCaseInsensitiveContains(query)) {
            if !items.contains(where: { $0.url == item.url }) {
                items.append(OmniboxResult(id: item.id, title: item.title, subtitle: item.url, kind: .history, url: item.url))
            }
        }
        return Array(items.prefix(7))
    }
    public var body: some View {
        HStack(spacing: 9) {
            Image(systemName: focused ? "magnifyingglass" : (window.selected?.isSecure == false ? "exclamationmark.triangle" : "lock"))
                .font(.system(size: 11)).foregroundStyle(theme.muted)
            TextField("Search Google or enter URL", text: $draft)
                .font(AetherType.body(12))
                .textFieldStyle(.plain)
                .foregroundStyle(theme.ink)
                .focused($focused)
                .onSubmit { commit() }
                .onChange(of: draft) { _, _ in showingSuggestions = focused && !draft.isEmpty; selection = 0 }
                .onChange(of: focused) { _, now in
                    draft = now ? (window.selected?.url ?? "") : displayAddress(window.selected?.url)
                    showingSuggestions = now && !draft.isEmpty
                }
                .onChange(of: window.addressFocusNonce) { _, _ in focused = true }
                .onChange(of: window.selectedID) { _, _ in
                    draft = displayAddress(window.selected?.url); showingSuggestions = false
                }
                .onChange(of: window.selected?.url) { _, url in
                    if !focused { draft = displayAddress(url) }
                }
            if focused && !draft.isEmpty {
                Button { draft = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(theme.muted)
                }.buttonStyle(.plain).help("Clear address")
            }
            if !focused, let tab = window.selected, tab.url != nil {
                ChromeButton(window.workspace.isBookmarked(tab.url, profileID: window.activeProfileID) ? "star.fill" : "star",
                             help: "Bookmark this page", size: 23) {
                    if let url = tab.url {
                        window.workspace.toggleBookmark(profileID: window.activeProfileID, title: tab.title, url: url)
                    }
                }
            }
        }
        .padding(.leading, 12).padding(.trailing, 6)
        .frame(height: 33)
        .background { AetherGlassBackdrop(radius: 8) }
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(focused ? theme.muted.opacity(0.54) : theme.line.opacity(0.70), lineWidth: 1))
        .onAppear { draft = displayAddress(window.selected?.url) }
        .popover(isPresented: $showingSuggestions, arrowEdge: .bottom) {
            VStack(spacing: 3) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.muted)
                    Text("Search or open \"\(draft)\"").lineLimit(1)
                    Spacer()
                    Text("↵").foregroundStyle(theme.soft)
                }
                .font(AetherType.body(12)).padding(10)
                .background(selection == 0 ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle()).onTapGesture { commit() }
                ForEach(Array(matches.enumerated()), id: \.element.id) { offset, item in
                    Button { choose(item) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.kind.symbol).font(.system(size: 12)).frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(AetherType.medium(12)).lineLimit(1)
                                Text(item.subtitle).font(AetherType.body(11)).foregroundStyle(theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                        }
                        .foregroundStyle(theme.ink).padding(10)
                        .background(selection == offset + 1 ? theme.selection : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
            }
            .padding(7).frame(width: 460).background { AetherPopoverBackground() }
        }
    }
    private func displayAddress(_ url: String?) -> String {
        guard let url else { return "" }
        if window.workspace.preferences.showFullAddress { return url }
        return URL(string: url)?.host ?? url
    }
    private func commit() {
        if selection > 0 && selection <= matches.count { choose(matches[selection - 1]); return }
        let text = draft
        focused = false; showingSuggestions = false
        window.navigateSelected(text)
    }
    private func choose(_ item: OmniboxResult) {
        focused = false; showingSuggestions = false
        if item.kind == .tab { window.select(item.id) }
        else if let url = item.url { window.navigateSelected(url) }
    }
}

private struct OmniboxResult: Identifiable {
    enum Kind {
        case tab, bookmark, history
        var symbol: String {
            switch self { case .tab: "square.on.square"; case .bookmark: "star"; case .history: "clock" }
        }
    }
    var id: UUID
    var title: String
    var subtitle: String
    var kind: Kind
    var url: String?
}
