import SwiftUI

public struct AetherCommandPalette: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var query = ""
    @FocusState private var fieldFocused: Bool
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var skin: AetherSurfaceStyle {
        surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
    }

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
            Rectangle().fill(skin.separator).frame(height: 1)
            row("History", nil, symbol: .history, chevron: true) { close(); window.showHistoryPanel() }
            row("Bookmarks", nil, symbol: .bookmarks, chevron: true) { close(); window.showBookmarksPanel() }
        }
        .padding(8)
        .frame(width: 322)
        .frame(maxHeight: 520, alignment: .top)
        .background {
            AetherPopoverBackground()
        }
        .aetherGlassShadow(dark: skin.isDark)
        .onAppear { fieldFocused = true }
        .onExitCommand { close() }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            BrowserIconView(icon: .search, tint: skin.secondaryIcon).iconSize(16)
            TextField("Search", text: $query, prompt: Text("Search").foregroundStyle(skin.metadataText))
                .textFieldStyle(.plain)
                .font(AetherType.body(16))
                .foregroundStyle(skin.primaryText)
                .focused($fieldFocused)
            HStack(spacing: 2) {
                AetherCustomIconView(.kbdShift, tint: skin.metadataText, size: 9)
                AetherCustomIconView(.kbdCommand, tint: skin.metadataText, size: 9)
                Text("A")
                    .font(AetherType.caption(10)).foregroundStyle(skin.metadataText)
            }
            .tracking(0.5)
        }
        .padding(.horizontal, 11)
        .frame(height: 42)
        .background {
            // A translucent well on the frosted card. An opaque near-black bar
            // here is a rectangle pasted onto glass, not part of the surface.
            AetherSurfaceFieldBackground(radius: AetherMetrics.fieldRadius)
        }
        .accessibilityLabel("Search tabs, history and bookmarks")
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AetherType.sectionHeader(12))
                .foregroundStyle(skin.secondaryText)
                .padding(.leading, 9).padding(.vertical, 4)
            content()
        }
    }

    @ViewBuilder private func emptyRow(_ text: String) -> some View {
        Text(text).font(AetherType.body(12)).foregroundStyle(skin.metadataText).padding(12)
    }

    @ViewBuilder private func row(_ title: String, _ subtitle: String?, url: String? = nil, symbol: AetherSymbol? = nil,
                                  selected: Bool = false, chevron: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CommandPaletteRowSurface(selected: selected, skin: skin) {
            HStack(spacing: 10) {
                if let url {
                    DomainIcon(url, size: 16)
                } else if let symbol {
                    AetherSymbolView(symbol, tint: skin.secondaryIcon, size: 16)
                } else {
                    DomainIcon(nil, size: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(AetherType.body(13)).foregroundStyle(skin.primaryText).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(AetherType.caption(11))
                            .foregroundStyle(skin.metadataText).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if selected {
                    AetherSymbolView(.confirm, tint: skin.secondaryIcon, size: 11)
                } else if chevron {
                    AetherSymbolView(.forward, tint: skin.secondaryIcon, size: 10)
                }
            }
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
    let skin: AetherSurfaceStyle
    let content: Content

    init(selected: Bool, skin: AetherSurfaceStyle, @ViewBuilder content: () -> Content) {
        self.selected = selected
        self.skin = skin
        self.content = content()
    }

    var body: some View {
        content
            .background {
                ZStack {
                    if selected {
                        // A subtle translucent highlight over the blur, never a
                        // flat grey slab.
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(skin.selectionFill)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(skin.hoverFill)
                    }
                }
            }
            .onHover { hovering = $0 }
            .animation(AetherMotion.selection(reduced), value: selected)
            .animation(AetherMotion.hover(reduced), value: hovering)
    }
}

private struct AetherPaletteRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    let reduced: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { AetherFocusedFill(radius: 8) }
            .focusEffectDisabled()
            .modifier(AetherPointingCursor())
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced || reducedMotion), value: configuration.isPressed)
    }
}
