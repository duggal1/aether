import SwiftUI

public struct AetherCommandPalette: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var query = ""
    @FocusState private var fieldFocused: Bool
    @Namespace private var glassNS
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var appearance: AetherChromeAppearance { chrome ?? (theme.dark ? .dark : .light) }

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
                .background { AetherOverlayScrollerTuning() }
            }
            Rectangle().fill(appearance.secondary.opacity(0.18)).frame(height: 1)
            row("History", nil, symbol: .history, chevron: true) { close(); window.showsHistory = true }
            row("Bookmarks", nil, symbol: .bookmarks, chevron: true) { close(); window.showsBookmarks = true }
        }
        .padding(8)
        .frame(width: 322)
        .frame(maxHeight: 520, alignment: .top)
        .background {
            AetherPopoverBackground()
        }
        .aetherGlassShadow(dark: appearance.isDark)
        .onAppear { fieldFocused = true }
        .onExitCommand { close() }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            BrowserIconView(icon: .search, tint: appearance.secondary).iconSize(16)
            TextField("Search", text: $query, prompt: Text("Search").foregroundStyle(appearance.secondary))
                .textFieldStyle(.plain)
                .font(AetherType.body(16))
                .foregroundStyle(appearance.text)
                .focused($fieldFocused)
            HStack(spacing: 2) {
                AetherCustomIconView(.kbdShift, tint: appearance.secondary, size: 9)
                AetherCustomIconView(.kbdCommand, tint: appearance.secondary, size: 9)
                Text("A")
                    .font(AetherType.caption(10)).foregroundStyle(appearance.secondary)
            }
            .tracking(0.5)
        }
        .padding(.horizontal, 11)
        .frame(height: 42)
        
        .accessibilityLabel("Search tabs, history and bookmarks")
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AetherType.sectionHeader(12))
                .foregroundStyle(appearance.secondary)
                .padding(.leading, 9).padding(.vertical, 4)
            content()
        }
    }

    @ViewBuilder private func emptyRow(_ text: String) -> some View {
        Text(text).font(AetherType.body(12)).foregroundStyle(appearance.secondary).padding(12)
    }

    @ViewBuilder private func row(_ title: String, _ subtitle: String?, url: String? = nil, symbol: AetherSymbol? = nil,
                                  selected: Bool = false, chevron: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CommandPaletteRowSurface(selected: selected, appearance: appearance) {
            HStack(spacing: 10) {
                if let url {
                    DomainIcon(url, size: 16)
                } else if let symbol {
                    AetherSymbolView(symbol, tint: appearance.secondary, size: 16)
                } else {
                    DomainIcon(nil, size: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(AetherType.body(13)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(AetherType.caption(11)).foregroundStyle(appearance.secondary).lineLimit(1) }
                }
                Spacer(minLength: 4)
                if selected {
                    AetherSymbolView(.confirm, tint: appearance.secondary, size: 11)
                } else if chevron {
                    AetherSymbolView(.forward, tint: appearance.secondary, size: 10)
                }
            }
            .foregroundStyle(appearance.text)
            .padding(.horizontal, 9)
            .frame(height: subtitle == nil ? 40 : 52)
            .contentShape(Rectangle())
            }
        }
        .buttonStyle(AetherPaletteRowStyle(reduced: reduced))
        .focusEffectDisabled()
    }

    private func close() { window.showsTabSearch = false }
}

private struct CommandPaletteRowSurface<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovering = false
    let selected: Bool
    let appearance: AetherChromeAppearance
    let content: Content

    init(selected: Bool, appearance: AetherChromeAppearance, @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.appearance = appearance
        self.content = content()
    }

    var body: some View {
        content
            .background { AetherInteractionSurface(active: selected || hovering, radius: 8, selected: selected, hovering: hovering) }
            .onHover { hovering = $0 }
            .animation(AetherMotion.hover(reduced), value: hovering)
    }
}

private struct AetherPaletteRowStyle: ButtonStyle {
    @Environment(\.aetherTheme) private var theme
    let reduced: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { AetherFocusedFill(radius: 8) }
            .focusEffectDisabled()
            .pointerStyle(.link)
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
    }
}
