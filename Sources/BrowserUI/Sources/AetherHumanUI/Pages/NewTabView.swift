import SwiftUI

public struct NewTabView: View {
    @Environment(\.aetherTheme) private var theme
    @BrowserState private var editing: BrowserShortcut?
    @BrowserState private var adding = false
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }
    private let columns = Array(repeating: GridItem(.fixed(90), spacing: 23), count: 4)
    public var body: some View {
        VStack(spacing: 29) {
            AetherMark()
            LazyVGrid(columns: columns, alignment: .center, spacing: 21) {
                ForEach(window.workspace.shortcuts) { item in
                    shortcut(item)
                }
                Button { adding = true } label: {
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 12).fill(theme.surface)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12).strokeBorder(theme.line, lineWidth: 1)
                            }
                            .overlay(Image(systemName: "plus").font(.system(size: 17, weight: .light)).foregroundStyle(theme.muted))
                            .frame(width: 55, height: 55)
                        Text("Add").font(AetherType.body(11)).foregroundStyle(theme.muted)
                    }.frame(width: 90, height: 85)
                }.buttonStyle(.plain).help("Add shortcut")
            }
            .frame(width: 429)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -34)
        .sheet(isPresented: $adding) { ShortcutEditor(workspace: window.workspace, shortcut: nil) }
        .sheet(item: $editing) { item in ShortcutEditor(workspace: window.workspace, shortcut: item) }
    }
    private func shortcut(_ item: BrowserShortcut) -> some View {
        Button { window.navigateSelected(item.url) } label: {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12).fill(theme.surface)
                    .overlay(DomainIcon(item.url, size: 27))
                    .frame(width: 55, height: 55)
                Text(item.name).font(AetherType.body(11)).foregroundStyle(theme.muted)
                    .lineLimit(1).frame(width: 88)
            }.frame(width: 90, height: 85)
        }
        .buttonStyle(.plain)
        .help(item.url)
        .contextMenu {
            Button("Open in New Tab") { _ = window.newTab(url: item.url) }
            Button("Edit Shortcut") { editing = item }
            Button("Remove Shortcut", role: .destructive) { window.workspace.removeShortcut(item.id) }
        }
    }
}

private struct AetherMark: View {
    @Environment(\.aetherTheme) private var theme
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15).fill(theme.surface).frame(width: 58, height: 58)
            Image(systemName: "asterisk").font(.system(size: 21, weight: .ultraLight)).foregroundStyle(theme.ink)
        }
        .accessibilityLabel("Aether")
    }
}
