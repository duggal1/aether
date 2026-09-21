import SwiftUI

public struct GeneralSettingsView: View {
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        SettingsHelp("Choose how Aether starts and which profile new windows use.")
        AetherSection("On startup") {
            AetherRow("Restore previous windows", subtitle: "Continue where you left off.") {
                Toggle("Restore previous windows", isOn: Binding(get: { workspace.preferences.restoreWindows }, set: { workspace.preferences.restoreWindows = $0 })).labelsHidden().toggleStyle(.switch)
            }
        }
        AetherSection("New windows") {
            AetherRow("Open with profile") {
                Picker("Open with profile", selection: Binding(get: { workspace.defaultProfileID }, set: { workspace.setDefaultProfile($0) })) {
                    ForEach(workspace.profiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
                .help("Choose the profile for new windows")
                .accessibilityLabel("Open new windows with profile")
            }
        }
    }
}
