import SwiftUI

public struct ProfilesSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @BrowserState private var createName = ""
    @BrowserState private var showCreate = false
    @BrowserState private var editing: UUID?
    @BrowserState private var editingName = ""
    @BrowserState private var deleting: UUID?
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    private var skin: AetherSurfaceStyle {
        if let surface, !surface.isHomepage { return surface }
        return AetherSurfaceResolver.style(theme.dark ? .darkWebsite : .lightWebsite,
                                            darkHomepage: theme.dark)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Spaces")
            SettingsCard {
                ForEach(Array(workspace.profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(profile.name,
                                subtitle: profile.id == workspace.defaultProfileID ? "Default for new windows" : nil,
                                symbol: "person.crop.circle") {
                        Menu {
                            Button("Rename") { editing = profile.id; editingName = profile.name }
                            Button("Use for New Windows") { workspace.setDefaultProfile(profile.id) }
                            Divider()
                            Button("Delete Space", role: .destructive) { deleting = profile.id }
                                .disabled(workspace.profiles.count == 1)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(AetherType.symbol(15))
                                .foregroundStyle(skin.isDark ? Color.white : skin.secondaryIcon)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                }
            }
        }
        HStack {
            Spacer()
            Button { showCreate = true } label: {
                Label("Create Space", systemImage: "plus")
                    .font(AetherType.body(13))
                    .foregroundStyle(skin.primaryText)
            }
            .buttonStyle(.plain)
            .aetherPointingCursor()
            .focusEffectDisabled()
        }
        .sheet(isPresented: $showCreate) {
            editor(title: "Create Space", value: $createName) {
                _ = workspace.createProfile(createName)
                createName = ""; showCreate = false
            } cancel: { showCreate = false }
        }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            editor(title: "Rename Space", value: $editingName) {
                if let editing { workspace.renameProfile(editing, to: editingName) }
                editing = nil
            } cancel: { editing = nil }
        }
        .confirmationDialog("Delete this space and its saved data?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Space", role: .destructive) {
                if let deleting { _ = workspace.deleteProfile(deleting) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("Engine-side data deletion needs the engine adapter.") }
    }

    private func editor(title: String, value: Binding<String>, save: @escaping () -> Void, cancel: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title)
                .font(AetherType.title(20)).tracking(AetherTracking.heading)
                .foregroundStyle(skin.primaryText)
            AetherField("Space name", text: value)
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel", action: cancel)
                    .aetherButton()
                    .focusEffectDisabled()
                Button("Save", action: save).disabled(value.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    .aetherProminentButton()
                    .keyboardShortcut(.defaultAction)
                    .focusEffectDisabled()
            }
        }
        .padding(24)
        .frame(width: 350)
        .background { SettingsBlurBackground() }
        .environment(\.aetherSurfaceStyle, skin)
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.cardRadius, style: .continuous))
        .presentationBackground(.clear)
    }
}
