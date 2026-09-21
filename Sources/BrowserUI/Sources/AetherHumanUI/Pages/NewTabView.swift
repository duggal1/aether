import SwiftUI

public struct NewTabView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var editing: BrowserShortcut?
    @BrowserState private var adding = false
    @BrowserState private var hoveredShortcut: UUID?
    @BrowserState private var ask = ""
    @FocusState private var askFocused: Bool
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private let columns = Array(repeating: GridItem(.fixed(108), spacing: 16), count: 4)

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    AetherLogo()
                        .frame(width: 46)
                        .accessibilityLabel("Aether")
                    askCard
                    LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                        ForEach(window.workspace.shortcuts) { item in shortcut(item) }
                        addTile
                    }
                    .frame(maxWidth: 480)
                    .padding(.top, 8)
                }
                .frame(maxWidth: 696)
                .padding(.horizontal, 32)
                .padding(.top, max(42, geometry.size.height * 0.18))
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
    }

    private var canSubmit: Bool { !ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var askCard: some View {
        HStack(spacing: 11) {
            BrowserIconView(icon: .search, tint: theme.fieldIcon).iconSize(16)
            TextField("Ask anything…", text: $ask,
                      prompt: Text("Ask anything…").foregroundStyle(theme.placeholder))
                .textFieldStyle(.plain)
                .font(AetherType.placeholder(14))
                .foregroundStyle(theme.ink)
                .focused($askFocused)
                .onSubmit(submitAsk)
            Button(action: submitAsk) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(canSubmit ? theme.ink : theme.muted)
                    .frame(width: 26, height: 26)
                    .background(canSubmit ? theme.control : theme.raised, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(AetherPressStyle(reduced: reduced))
            .aetherPointingCursor()
            .disabled(!canSubmit)
            .help("Search or open address")
            .accessibilityLabel("Search or open address")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(theme.card.opacity(0.35), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .animation(AetherMotion.focus(reduced), value: askFocused)
    }

    private func submitAsk() {
        let text = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        ask = ""
        window.navigateSelected(text, intelligence: true)
    }

    private func shortcut(_ item: BrowserShortcut) -> some View {
        ZStack(alignment: .topTrailing) {
            Button { window.navigateSelected(item.url) } label: {
                VStack(spacing: 9) {
                    DomainIcon(item.url, size: 28)
                        .frame(width: 54, height: 54)
                        .background(theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
            .contextMenu { shortcutActions(item) }

            Menu { shortcutActions(item) } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.textStrong)
                    .frame(width: 23, height: 23)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.top, 2)
            .padding(.trailing, 3)
            .opacity(hoveredShortcut == item.id ? 1 : 0)
            .allowsHitTesting(hoveredShortcut == item.id)
            .aetherPointingCursor()
            .help("Shortcut actions for \\(item.name)")
            .accessibilityLabel("Shortcut actions for \\(item.name)")
        }
        .frame(width: 108, height: 94)
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(AetherMotion.focus(reduced)) {
                hoveredShortcut = inside ? item.id : (hoveredShortcut == item.id ? nil : hoveredShortcut)
            }
        }
    }

    @ViewBuilder private func shortcutActions(_ item: BrowserShortcut) -> some View {
        Button("Open in New Tab") { _ = window.newTab(url: item.url) }
        Button(item.isPinned ? "Unpin from Toolbar" : "Pin to Toolbar") {
            window.workspace.toggleShortcutPin(item.id)
        }
        Button("Edit Shortcut") { editing = item }
        Button("Remove Shortcut", role: .destructive) { window.workspace.removeShortcut(item.id) }
    }

    private var addTile: some View {
        Button { adding = true } label: {
            VStack(spacing: 9) {
                BrowserIconView(icon: .plus, tint: theme.muted)
                    .iconSize(17)
                    .frame(width: 54, height: 54)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
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
