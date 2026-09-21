import SwiftUI

public struct NewTabView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var editing: BrowserShortcut?
    @BrowserState private var adding = false
    @BrowserState private var ask = ""
    @FocusState private var askFocused: Bool
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private let columns = Array(repeating: GridItem(.fixed(96), spacing: 18), count: 4)

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 26) {
                    AetherMark()
                    askCard
                    if window.arrangement == .top || window.sidebarCollapsed || !window.workspace.preferences.showFavorites {
                        LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                            ForEach(window.workspace.shortcuts) { item in shortcut(item) }
                            addTile
                        }
                        .frame(maxWidth: 438)
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: 651)
                .padding(.horizontal, 32)
                .padding(.top, max(48, geometry.size.height * 0.25))
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background {
            LinearGradient(colors: [theme.canvas, AetherPalette.panelBottom(theme.dark)],
                           startPoint: .top, endPoint: .bottom)
        }
        .sheet(isPresented: $adding) { ShortcutEditor(workspace: window.workspace, shortcut: nil) }
        .sheet(item: $editing) { item in ShortcutEditor(workspace: window.workspace, shortcut: item) }
        .task {
            AetherFaviconStore.shared.prefetch(window.workspace.shortcuts.compactMap { URL(string: $0.url)?.host })
        }
    }

    private var canSubmit: Bool { !ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var askCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                BrowserIconView(icon: .search, tint: theme.muted).iconSize(17)
                TextField("Ask anything…", text: $ask,
                          prompt: Text("Ask anything…").foregroundStyle(theme.placeholder))
                    .textFieldStyle(.plain)
                    .font(AetherType.placeholder(16))
                    .foregroundStyle(theme.ink)
                    .focused($askFocused)
                    .onSubmit(submitAsk)
            }
            .frame(height: 28)
            .padding(.horizontal, 6)
            HStack {
                Button { adding = true } label: {
                    Label("Add shortcut", systemImage: "plus")
                        .font(AetherType.body(13))
                        .foregroundStyle(theme.muted)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(theme.hover.opacity(0.6), in: Capsule())
                }
                .buttonStyle(AetherPressStyle(reduced: reduced))
                Spacer()
                Text(window.workspace.preferences.provider.rawValue)
                    .font(AetherType.caption(12)).foregroundStyle(theme.muted)
                Button(action: submitAsk) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(canSubmit ? theme.ink : theme.soft)
                        .frame(width: 32, height: 32)
                        .background(theme.hover, in: Circle())
                }
                .buttonStyle(AetherPressStyle(reduced: reduced))
                .disabled(!canSubmit)
                .help("Search or open address")
                .accessibilityLabel("Search or open address")
            }
        }
        .padding(16)
        .background { AetherGlassBackdrop(radius: 20) }
        .animation(AetherMotion.focus(reduced), value: askFocused)
    }

    private func submitAsk() {
        let text = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        ask = ""
        window.navigateSelected(text)
    }

    private func shortcut(_ item: BrowserShortcut) -> some View {
        Button { window.navigateSelected(item.url) } label: {
            VStack(spacing: 9) {
                DomainIcon(item.url, size: 24)
                    .frame(width: 54, height: 54)
                    .background { AetherCardBackground(radius: 12) }
                Text(item.name)
                    .font(AetherType.body(11)).foregroundStyle(theme.muted)
                    .lineLimit(1).frame(width: 92)
            }
            .frame(width: 96, height: 84)
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .help(item.url)
        .contextMenu {
            Button("Open in New Tab") { _ = window.newTab(url: item.url) }
            Button("Edit Shortcut") { editing = item }
            Button("Remove Shortcut", role: .destructive) { window.workspace.removeShortcut(item.id) }
        }
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
            .frame(width: 96, height: 84)
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .help("Add shortcut")
    }
}

private struct AetherMark: View {
    var body: some View {
        AetherLogo()
            .frame(width: 38, height: 38)
            .frame(width: 68, height: 64)
            .background { AetherGlassBackdrop(radius: 22) }
            .accessibilityLabel("Aether")
    }
}
