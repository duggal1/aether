import SwiftUI

public struct ShortcutEditor: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @BrowserState private var name: String
    @BrowserState private var url: String
    let workspace: BrowserWorkspace
    let shortcut: BrowserShortcut?
    public init(workspace: BrowserWorkspace, shortcut: BrowserShortcut?) {
        self.workspace = workspace; self.shortcut = shortcut
        _name = State(initialValue: shortcut?.name ?? "")
        _url = State(initialValue: shortcut?.url ?? "")
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(shortcut == nil ? "Add Shortcut" : "Edit Shortcut")
                .font(AetherType.title(22)).foregroundStyle(theme.heading)
            VStack(alignment: .leading, spacing: 7) {
                Text("Name").font(AetherType.medium(12)).foregroundStyle(theme.muted)
                AetherField("Website name", text: $name)
                Text("Address").font(AetherType.medium(12)).foregroundStyle(theme.muted)
                    .padding(.top, 8)
                AetherField("https://example.com", text: $url)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if let shortcut { workspace.editShortcut(shortcut.id, name: name, url: url) }
                    else { workspace.addShortcut(name: name, url: url) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || AddressResolver.resolve(url) == nil)
            }
        }.padding(24).frame(width: 380).background(theme.canvas)
    }
}
