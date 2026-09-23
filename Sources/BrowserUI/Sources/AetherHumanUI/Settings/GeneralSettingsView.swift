import SwiftUI

public struct GeneralSettingsView: View {
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        AetherSection("On startup") {
            AetherRow("Restore previous windows", symbol: "power") {
                Toggle("Restore previous windows", isOn: Binding(get: { workspace.preferences.restoreWindows }, set: { workspace.preferences.restoreWindows = $0 })).labelsHidden().toggleStyle(.switch)
            }
        }
        AetherSection("New windows") {
            AetherRow("Open with profile", symbol: "person.crop.circle") {
                AetherDropdown(
                    selection: Binding(get: { workspace.defaultProfileID }, set: { workspace.setDefaultProfile($0) }),
                    options: workspace.profiles.map { AetherDropdownOption(value: $0.id, title: $0.name) },
                    help: "Choose the profile for new windows",
                    label: "Open new windows with profile")
            }
        }
    }
}
