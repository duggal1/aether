import SwiftUI

public struct AetherCommandPalette: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var query = ""
    @FocusState private var fieldFocused: Bool
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func matches(_ title: String, _ subtitle: String?) -> Bool {
        guard !trimmed.isEmpty else { return true }
        return title.localizedCaseInsensitiveContains(trimmed) || (subtitle?.localizedCaseInsensitiveContains(trimmed) ?? false)
    }
    private var limit: Int { trimmed.isEmpty ? 5 : 9 }
    private var tabMatches: [BrowserTab] {
        window.tabs.filter { matches($0.title, $0.url) }.prefix(limit).map { $0 }
    }
    private var closedMatches: [ClosedTab] {
        window.closedTabs.filter { $0.profileID == window.activeProfileID && matches($0.title, $0.url) }.prefix(limit).map { $0 }
    }
    private var historyMatches: [BrowserVisit] {
        window.workspace.visits.filter { $0.profileID == window.activeProfileID && matches($0.title, $0.url) }.prefix(limit).map { $0 }
    }
    private var bookmarkMatches: [BrowserBookmark] {
        window.workspace.bookmarks(for: window.activeProfileID).filter { matches($0.title, $0.url) }.prefix(limit).map { $0 }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    section("Open Tabs") {
                        if tabMatches.isEmpty {
                            emptyRow("No matching tabs")
                        } else {
                            ForEach(tabMatches) { tab in
                                row(tab.title, tab.url, url: tab.url, selected: tab.id == window.selectedID) {
                                    window.select(tab.id)
                                    close()
                                }
                            }
                        }
                    }
                    if !closedMatches.isEmpty {
                        section("Recently Closed") {
                            ForEach(closedMatches) { item in
                                row(item.title, nil, symbol: .recentlyClosed) {
                                    window.restoreClosed(item.id)
                                    close()
                                }
                            }
                        }
                    }
                    if !historyMatches.isEmpty {
                        section("History") {
                            ForEach(historyMatches) { visit in
                                row(visit.title, visit.url, url: visit.url, chevron: true) {
                                    window.navigateSelected(visit.url)
                                    close()
                                }
                            }
                        }
                    }
                    if !bookmarkMatches.isEmpty {
                        section("Bookmarks") {
                            ForEach(bookmarkMatches) { mark in
                                row(mark.title, mark.url, url: mark.url, chevron: true) {
                                    window.navigateSelected(mark.url)
                                    close()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().opacity(0.4)
            row("History", nil, symbol: .history, chevron: true) { close(); window.showsHistory = true }
            row("Bookmarks", nil, symbol: .bookmarks, chevron: true) { close(); window.showsBookmarks = true }
        }
        .padding(13)
        .frame(width: 348)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
                .fill(theme.raised)
        }
        .aetherFloatingShadow(dark: theme.dark)
        .onAppear { fieldFocused = true }
        .onExitCommand { close() }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            BrowserIconView(icon: .search, tint: theme.muted).iconSize(13)
            TextField("Search tabs, history, bookmarks", text: $query)
                .textFieldStyle(.plain)
                .font(AetherType.body(13))
                .foregroundStyle(theme.ink)
                .focused($fieldFocused)
            Text("\u{21E7}\u{2318}A")
                .font(AetherType.caption(10)).foregroundStyle(theme.soft)
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(theme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("Search tabs, history and bookmarks")
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(AetherType.sectionHeader(10))
                .tracking(0.4)
                .foregroundStyle(theme.soft)
                .padding(.leading, 9).padding(.vertical, 4)
            content()
        }
    }

    @ViewBuilder private func emptyRow(_ text: String) -> some View {
        Text(text).font(AetherType.body(12)).foregroundStyle(theme.muted).padding(12)
    }

    @ViewBuilder private func row(_ title: String, _ subtitle: String?, url: String? = nil, symbol: AetherSymbol? = nil,
                                  selected: Bool = false, chevron: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let url {
                    DomainIcon(url, size: 18)
                } else if let symbol {
                    AetherSymbolView(symbol, tint: theme.muted, size: 13)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(AetherType.rowTitle(12)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(AetherType.caption(11)).foregroundStyle(theme.muted).lineLimit(1) }
                }
                Spacer(minLength: 4)
                if selected {
                    AetherSymbolView(.confirm, tint: theme.muted, size: 11)
                } else if chevron {
                    AetherSymbolView(.forward, tint: theme.soft, size: 10)
                }
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 9)
            .frame(height: subtitle == nil ? 30 : 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(AetherPaletteRowStyle(reduced: reduced))
    }

    private func close() { window.showsTabSearch = false }
}

private struct AetherPaletteRowStyle: ButtonStyle {
    @Environment(\.aetherTheme) private var theme
    let reduced: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
    }
}
