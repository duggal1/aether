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
        VStack(spacing: 26) {
            AetherMark()
            askCapsule
            LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                ForEach(window.workspace.shortcuts) { item in shortcut(item) }
                addTile
            }
            .frame(width: 438)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -26)
        .sheet(isPresented: $adding) { ShortcutEditor(workspace: window.workspace, shortcut: nil) }
        .sheet(item: $editing) { item in ShortcutEditor(workspace: window.workspace, shortcut: item) }
        .task {
            AetherFaviconStore.shared.prefetch(window.workspace.shortcuts.compactMap { URL(string: $0.url)?.host })
        }
    }

    private var askCapsule: some View {
        HStack(spacing: 10) {
            BrowserIconView(icon: .search, tint: theme.muted).iconSize(14)
            TextField("Ask anything\u{2026}", text: $ask)
                .textFieldStyle(.plain)
                .font(AetherType.placeholder(14))
                .foregroundStyle(theme.ink)
                .focused($askFocused)
                .onSubmit(submitAsk)
            if !ask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: submitAsk) {
                    BrowserIconView(icon: .arrowUpRight, tint: theme.ink).iconSize(12)
                        .frame(width: 24, height: 24)
                        .background(theme.hover, in: Circle())
                }
                .buttonStyle(AetherPressStyle(reduced: reduced))
                .help("Open")
            }
        }
        .padding(.leading, 14).padding(.trailing, 8)
        .frame(height: 42)
        .frame(width: 438)
        .background { AetherCardBackground(radius: 21) }
        .aetherRestingShadow(dark: theme.dark)
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
                DomainIcon(item.url, size: 26)
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
            .frame(width: 30, height: 30)
            .frame(width: 54, height: 54)
            .background { AetherCardBackground(radius: 14) }
            .accessibilityLabel("Aether")
    }
}
