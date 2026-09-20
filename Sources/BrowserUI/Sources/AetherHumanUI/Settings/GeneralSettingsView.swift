import SwiftUI

public struct GeneralSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        SettingsHelp("Choose how Aether starts and which profile new windows use.")
        AetherSection("On startup") {
            AetherRow("Restore previous windows", subtitle: "Requires engine-backed page restoration, not just saved tab labels.") {
                Toggle("Restore previous windows", isOn: Binding(get: { workspace.preferences.restoreWindows }, set: { workspace.preferences.restoreWindows = $0 })).labelsHidden()
            }
        }
        AetherSection("New windows") {
            AetherRow("Open with profile") {
                Picker("Profile", selection: Binding(get: { workspace.defaultProfileID }, set: { workspace.setDefaultProfile($0) })) {
                    ForEach(workspace.profiles) { Text($0.name).tag($0.id) }
                }.labelsHidden().frame(width: 160)
            }
        }
        SettingsHelp("Browser data, JavaScript execution, renderer behavior and profile security remain owned by the existing Aether engine.")
    }
}
