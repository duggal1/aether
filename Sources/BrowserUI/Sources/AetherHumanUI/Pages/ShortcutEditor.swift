import SwiftUI

public struct ShortcutEditor: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @BrowserState private var name: String
    @BrowserState private var url: String
    let workspace: BrowserWorkspace
    let shortcut: BrowserShortcut?

    public init(workspace: BrowserWorkspace, shortcut: BrowserShortcut?) {
        self.workspace = workspace
        self.shortcut = shortcut
        _name = State(initialValue: shortcut?.name ?? "")
        _url = State(initialValue: shortcut?.url ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading
            fields
            actions
        }
        .padding(22)
        .frame(width: 380)
        .background(theme.inset)
    }

    private var heading: some View {
        Text(shortcut == nil ? "Add Shortcut" : "Edit Shortcut")
            .font(AetherType.panelTitle(20))
            .foregroundStyle(theme.heading)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 7) {
            label("Name")
            AetherField("Website name", text: $name)
            label("Address").padding(.top, 6)
            AetherField("https://example.com", text: $url)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(AetherType.sectionHeader(10))
            .tracking(0.4)
            .foregroundStyle(theme.soft)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel") { dismiss() }
                .aetherButtonStyle()
            Button("Save") { save() }
                .aetherProminentButtonStyle()
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && AddressResolver.resolve(url) != nil
    }

    private func save() {
        if let shortcut { workspace.editShortcut(shortcut.id, name: name, url: url) }
        else { workspace.addShortcut(name: name, url: url) }
        dismiss()
    }
}
