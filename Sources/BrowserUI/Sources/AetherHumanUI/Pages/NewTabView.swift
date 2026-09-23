import SwiftUI

public struct NewTabView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var editing: BrowserShortcut?
    @BrowserState private var adding = false
    @BrowserState private var hoveredShortcut: UUID?
    @State private var shortcutMenuID: UUID?
    @BrowserState private var ask = ""
    @FocusState private var askFocused: Bool
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private let columns = Array(repeating: GridItem(.fixed(108), spacing: 16), count: 4)

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 28) {
                    AetherLogo()
                        .opacity(scheme == .dark ? 0.82 : 0.72)
                        .frame(width: 52)
                        .accessibilityLabel("Aether")
                    askCard
                    if !canSubmit {
                        LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                            ForEach(window.workspace.shortcuts) { item in shortcut(item) }
                            addTile
                        }
                        .frame(maxWidth: 480)
                        .padding(.top, 10)
                    }
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, 32)
                .padding(.top, max(80, geometry.size.height * 0.25))
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(AetherPalette.canvas(theme.dark))
        .sheet(isPresented: $adding) { ShortcutEditor(workspace: window.workspace, shortcut: nil) }
        .sheet(item: $editing) { item in ShortcutEditor(workspace: window.workspace, shortcut: item) }
        .task {
            AetherFaviconStore.shared.prefetch(window.workspace.shortcuts.compactMap { URL(string: $0.url)?.host })
        }
        .onChange(of: ask) { _, value in
            window.suggestions.update(prefix: value, window: window, forceIntelligence: true)
        }
        .onChange(of: window.activeProfileID) { _, _ in
            window.suggestions.update(prefix: ask, window: window, forceIntelligence: true)
        }
        .onDisappear { window.suggestions.dismiss() }
    }

    private var canSubmit: Bool { !ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var askCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                BrowserIconView(icon: .search, tint: theme.muted).iconSize(17)
                TextField("Search or enter a website", text: $ask,
                          prompt: Text("Search or enter a website").foregroundStyle(theme.placeholder))
                    .textFieldStyle(.plain)
                    .font(AetherType.body(17))
                    .foregroundStyle(theme.ink)
                    .focused($askFocused)
                    .onSubmit(submitAsk)
                    .onKeyPress(.upArrow) { window.suggestions.move(-1); return .handled }
                    .onKeyPress(.downArrow) { window.suggestions.move(1); return .handled }
                    .accessibilityIdentifier("aether.center-search")
            }
            .padding(.horizontal, 22)
            .frame(height: 66)
            if canSubmit {
                suggestionRows
                HStack(spacing: 12) {
                    Button("Search Google") { searchGoogle() }
                        .font(AetherType.body(12))
                        .foregroundStyle(theme.muted)
                        .buttonStyle(.plain)
                        .aetherPointingCursor()
                    Spacer()
                    Button(action: submitAsk) {
                        HStack(spacing: 8) {
                            Text("Search with Jev")
                            Image(systemName: "return")
                        }
                        .font(AetherType.emphasis(12))
                        .foregroundStyle(theme.heading)
                        .padding(.horizontal, 15)
                        .frame(height: 32)
                        .background(theme.selected, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .aetherPointingCursor()
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
        }
        .background(theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(AetherMotion.focus(reduced), value: askFocused)
    }

    private var suggestionRows: some View {
        VStack(spacing: 2) {
            ForEach(Array(window.suggestions.rows.prefix(7).enumerated()), id: \.element.id) { index, row in
                Button { choose(row) } label: {
                    HStack(spacing: 13) {
                        suggestionIcon(row)
                            .frame(width: 19, height: 19)
                        Text(row.title)
                            .font(AetherType.body(14))
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let host = row.host, !row.title.localizedCaseInsensitiveContains(host) {
                            Text(host)
                                .font(AetherType.caption(12))
                                .foregroundStyle(theme.muted)
                                .lineLimit(1)
                        }
                        if index == window.suggestions.selected {
                            Image(systemName: "return")
                                .font(AetherType.symbol(12))
                                .foregroundStyle(theme.muted)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(index == window.suggestions.selected ? theme.selected : .clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .aetherPointingCursor()
                .accessibilityIdentifier("aether.center-suggestion.\(row.kind.rawValue)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }

    private func submitAsk() {
        let text = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let direct = AddressResolver.directURL(text) {
            ask = ""
            window.suggestions.dismiss()
            window.navigateSelected(direct.absoluteString)
            return
        }
        if let row = window.suggestions.selectedRow {
            choose(row)
            return
        }
        ask = ""
        window.suggestions.dismiss()
        window.navigateSelected(text, intelligence: true)
    }

    private func choose(_ row: OmniboxSuggestion) {
        window.suggestions.record(row, profileID: window.activeProfileID)
        let query = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        ask = ""
        window.suggestions.dismiss()
        if row.kind == .tab, let id = row.tabID {
            window.select(id)
        } else if let url = row.url {
            window.navigateSelected(url)
        } else {
            window.navigateSelected(row.completion ?? query, intelligence: true)
        }
    }

    private func searchGoogle() {
        let query = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = SearchProvider.google.searchURL(for: query,
            locality: window.workspace.preferences.searchLocality,
            localityTerms: window.workspace.preferences.localityQueryTerms) else { return }
        ask = ""
        window.suggestions.dismiss()
        window.navigateSelected(url.absoluteString)
    }

    @ViewBuilder private func suggestionIcon(_ row: OmniboxSuggestion) -> some View {
        switch row.kind {
        case .completion:
            BrowserIconView(icon: .search, tint: theme.muted).iconSize(16)
        case .open where row.url == nil:
            BrowserIconView(icon: .search, tint: theme.muted).iconSize(16)
        default:
            DomainIcon(row.url, size: 19)
        }
    }

    private func shortcut(_ item: BrowserShortcut) -> some View {
        ZStack(alignment: .topTrailing) {
            Button { window.navigateSelected(item.url) } label: {
                VStack(spacing: 9) {
                    DomainIcon(item.url, size: 28)
                        .frame(width: 54, height: 54)
.background(theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text(item.name)
                        .font(AetherType.body(12)).foregroundStyle(theme.muted)
                        .lineLimit(1).frame(maxWidth: 102)
                }
                .frame(width: 108, height: 94)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .aetherPointingCursor()
            .help(item.url)
            .overlay { SecondaryClickSurface { shortcutMenuID = item.id } }

            Button { shortcutMenuID = item.id } label: {
                Image(systemName: "ellipsis")
                    .font(AetherType.symbol(14))
                    .foregroundStyle(theme.textStrong)
                    .frame(width: 23, height: 23)
                    .background { AetherInteractionSurface(active: shortcutMenuID == item.id, radius: 6) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .padding(.top, 2)
            .padding(.trailing, 3)
            .opacity(hoveredShortcut == item.id ? 1 : 0)
            .animation(AetherMotion.focus(reduced), value: hoveredShortcut)
            .allowsHitTesting(hoveredShortcut == item.id)
            .aetherPointingCursor()
            .help("Shortcut actions for \(item.name)")
            .accessibilityLabel("Shortcut actions for \(item.name)")
        }
        .frame(width: 108, height: 94)
        .popover(isPresented: Binding(get: { shortcutMenuID == item.id }, set: { if !$0 { shortcutMenuID = nil } }), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) { shortcutActions(item) }
                .padding(7)
                .frame(width: 218)
                .background { AetherPopoverBackground() }
                .environment(\.aetherChromeAppearance, theme.dark ? .dark : .light)
                .preferredColorScheme(theme.dark ? .dark : .light)
                .presentationBackground(.clear)
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hoveredShortcut = inside ? item.id : (hoveredShortcut == item.id ? nil : hoveredShortcut)
        }
    }

    @ViewBuilder private func shortcutActions(_ item: BrowserShortcut) -> some View {
        shortcutAction("Open in New Tab", icon: .plus) { _ = window.newTab(url: item.url) }
        shortcutAction(item.isPinned ? "Unpin from Toolbar" : "Pin to Toolbar", icon: .pin) {
            window.workspace.toggleShortcutPin(item.id)
        }
        shortcutAction("Edit Shortcut", icon: .gear) { editing = item }
        shortcutAction("Remove Shortcut", icon: .close) { window.workspace.removeShortcut(item.id) }
    }

    private func shortcutAction(_ title: String, icon: BrowserIcon, action: @escaping () -> Void) -> some View {
        Button {
            shortcutMenuID = nil
            action()
        } label: {
            AetherMenuRow(radius: 6) {
                HStack(spacing: 10) {
                    BrowserIconView(icon: icon, tint: theme.muted).iconSize(14)
                    Text(title).font(AetherType.body(12)).foregroundStyle(theme.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .focusEffectDisabled()
    }

    private var addTile: some View {
        Button { adding = true } label: {
            VStack(spacing: 9) {
                BrowserIconView(icon: .plus, tint: theme.muted)
                    .iconSize(17)
                    .frame(width: 54, height: 54)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.soft.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                Text("Add")
                    .font(AetherType.body(11)).foregroundStyle(theme.muted)
            }
            .frame(width: 108, height: 94)
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .aetherPointingCursor()
        .help("Add shortcut")
    }
}
