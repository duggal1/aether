import SwiftUI

public struct ShortcutEditor: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduced
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

    private var skin: AetherSurfaceStyle {
        surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading
            fields
            actions
        }
        .padding(22)
        .frame(width: 380)
        .background { AetherSheetBackground() }
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.panelRadius, style: .continuous))
        .presentationBackground(.clear)
        .aetherSurfaceAppear()
    }

    private var heading: some View {
        Text(shortcut == nil ? "Add Shortcut" : "Edit Shortcut")
            .font(AetherType.panelTitle(20)).tracking(AetherTracking.heading)
            .foregroundStyle(skin.primaryText)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 7) {
            label("Name")
            AetherField("Website name", text: $name, horizontalPadding: 11)
            label("Address").padding(.top, 6)
            AetherField("https://example.com", text: $url, horizontalPadding: 11)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(AetherType.sectionHeader(10))
            .tracking(0.4)
            .foregroundStyle(skin.secondaryText)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(AetherModalActionButtonStyle(role: .secondary))
                .focusEffectDisabled()
                .aetherPointingCursor()
            Button { save() } label: {
                HStack(spacing: 7) {
                    AetherCustomIconView(.arrowReturn, tint: saveInk, size: 13)
                    Text("Save")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(AetherModalActionButtonStyle(role: .confirm))
            .focusEffectDisabled()
            .aetherPointingCursor()
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
    }

    // Ink for the primary action's icon: the inverse of the button fill, which
    // is the anchor the shape itself is in (dark button on light, light on dark).
    private var saveInk: Color { theme.background }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && AddressResolver.resolve(url) != nil
    }

    private func save() {
        if let shortcut { workspace.editShortcut(shortcut.id, name: name, url: url) }
        else { workspace.addShortcut(name: name, url: url) }
        dismiss()
    }
}
