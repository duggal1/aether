import SwiftUI

public struct ProfilesSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @BrowserState private var createName = ""
    @BrowserState private var showCreate = false
    @BrowserState private var editing: UUID?
    @BrowserState private var editingName = ""
    @BrowserState private var deleting: UUID?
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        SettingsHelp("Separate browsing identities. Aether's engine adapter must enforce independent cookies and site data for each profile.")
        AetherSection("Profiles") {
            ForEach(Array(workspace.profiles.enumerated()), id: \.element.id) { index, profile in
                if index > 0 { SettingsDivider() }
                AetherRow(profile.name, subtitle: profile.id == workspace.defaultProfileID ? "Default for new windows" : nil, symbol: "person.crop.circle") {
                    Menu {
                        Button("Rename") { editing = profile.id; editingName = profile.name }
                        Button("Use for New Windows") { workspace.setDefaultProfile(profile.id) }
                        Divider()
                        Button("Delete Profile", role: .destructive) { deleting = profile.id }
                            .disabled(workspace.profiles.count == 1)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15)).frame(width: 24)
                    }.menuStyle(.borderlessButton).frame(width: 35)
                }
            }
        }
        HStack {
            Spacer()
            Button { showCreate = true } label: { Label("Create Profile", systemImage: "plus") }
        }
        .sheet(isPresented: $showCreate) {
            editor(title: "Create Profile", value: $createName) {
                _ = workspace.createProfile(createName)
                createName = ""; showCreate = false
            } cancel: { showCreate = false }
        }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            editor(title: "Rename Profile", value: $editingName) {
                if let editing { workspace.renameProfile(editing, to: editingName) }
                editing = nil
            } cancel: { editing = nil }
        }
        .confirmationDialog("Delete this profile and its Aether shell data?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Profile", role: .destructive) {
                if let deleting { _ = workspace.deleteProfile(deleting) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("Engine-side profile data deletion requires the Aether engine adapter. Do not treat this shell action as secure data erasure.") }
    }
    private func editor(title: String, value: Binding<String>, save: @escaping () -> Void, cancel: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(title).font(AetherType.title(20))
            AetherField("Profile name", text: value)
            HStack {
                Spacer(); Button("Cancel", action: cancel)
                Button("Save", action: save).disabled(value.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 350).background(theme.canvas)
    }
}
