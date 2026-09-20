import SwiftUI

public struct OmniboxView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var focused = false
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
        HStack(spacing: 8) {
            BrowserIconView(icon: focused ? .search : (window.selected?.isSecure == false ? .warning : .lock),
                            tint: focused ? theme.ink : theme.muted)
                .iconSize(12)
            NativeAddressField(text: $draft, focused: $focused,
                fullAddress: window.selected?.url ?? "",
                placeholder: "Search \(window.workspace.preferences.provider.rawValue) or enter URL",
                focusRequest: window.addressFocusNonce,
                onSubmit: { commit() }, onEscape: { showingSuggestions = false })
                .frame(maxWidth: .infinity)
                .onChange(of: draft) { _, _ in
                    showingSuggestions = focused && !draft.isEmpty && draft != window.selected?.url
                    selection = 0
                }
                .onChange(of: focused) { _, now in
                    if !now { draft = displayAddress(window.selected?.url); showingSuggestions = false }
                }
                .onChange(of: window.selectedID) { _, _ in
                    draft = displayAddress(window.selected?.url); showingSuggestions = false
                }
                .onChange(of: window.selected?.url) { _, url in
                    if !focused { draft = displayAddress(url) }
                }
            if !focused {
                Button { window.navigateSelected("https://www.google.com/ai") } label: {
                    Text("AI Mode").font(AetherType.body(11)).foregroundStyle(theme.muted)
                }
                .buttonStyle(.plain)
                .help("Open Google AI Mode")
                .accessibilityIdentifier("aether.google-ai")
            }
            if focused && !draft.isEmpty {
                Button { draft = "" } label: {
                    BrowserIconView(icon: .close, tint: theme.muted).iconSize(11)
                }
                .buttonStyle(.plain)
                .help("Clear address")
            }
            Button {
                if let url = window.selected?.url {
                    window.workspace.toggleBookmark(profileID: window.activeProfileID, title: window.selected?.title ?? url, url: url)
                }
            } label: {
                BrowserIconView(icon: window.workspace.isBookmarked(window.selected?.url, profileID: window.activeProfileID) ? .doubleBookmark : .bookmark,
                                tint: theme.muted)
                    .iconSize(13)
            }
            .buttonStyle(.plain)
            .help("Bookmark this page")
        }
        .padding(.leading, 12).padding(.trailing, 6)
        .frame(height: 32)
        .background { AetherCardBackground(radius: 8) }
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(AetherMotion.focus(reduced), value: focused)
        .onAppear { draft = displayAddress(window.selected?.url) }
        .overlay(alignment: .topLeading) {
            if showingSuggestions { suggestions }
        }
    }

    private var suggestions: some View {
        VStack(spacing: 2) {
            suggestionRow(offset: 0, selected: selection == 0) {
                HStack(spacing: 9) {
                    BrowserIconView(icon: .search, tint: theme.muted).iconSize(12)
                    Text("Search or open \"\(draft)\"").lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\u{21A9}").foregroundStyle(theme.soft)
                }
            } action: { commit() }
            ForEach(Array(matches.enumerated()), id: \.element.id) { offset, item in
                suggestionRow(offset: offset + 1, selected: selection == offset + 1) {
                    HStack(spacing: 10) {
                        DomainIcon(item.url, size: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(AetherType.rowTitle(12)).lineLimit(1)
                            Text(item.subtitle).font(AetherType.caption(11)).foregroundStyle(theme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                    }
                } action: { choose(item) }
            }
        }
        .padding(6)
        .frame(maxWidth: 470)
        .fixedSize(horizontal: false, vertical: true)
        .background { AetherPopoverBackground() }
        .aetherFloatingShadow(dark: theme.dark)
        .offset(y: 38)
        .zIndex(2)
        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }

    @ViewBuilder private func suggestionRow<Content: View>(offset: Int, selected: Bool, @ViewBuilder content: () -> Content, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .font(AetherType.body(12))
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 9)
                .frame(height: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? theme.hover : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        var icon: BrowserIcon {
            switch self { case .tab: .web; case .bookmark: .bookmark; case .history: .history }
        }
    }
    var id: UUID
    var title: String
    var subtitle: String
    var kind: Kind
    var url: String?
}
