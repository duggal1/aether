import SwiftUI

public struct SearchSettingsView: View {
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        SettingsHelp("Aether uses one address field for website addresses and searches.")
        AetherSection("Search engine") {
            AetherRow("Default provider", subtitle: "Searches from the address bar use this provider.", symbol: "magnifyingglass") {
                AetherDropdown(
                    selection: Binding(get: { workspace.preferences.provider }, set: { workspace.preferences.provider = $0 }),
                    options: SearchProvider.allCases.map { AetherDropdownOption(value: $0, title: $0.rawValue) },
                    help: "Choose the default search provider",
                    label: "Default search provider")
            }
        }
        AetherSection("Address bar") {
            SettingsToggle("Show full website address", subtitle: "Keep the complete URL visible outside editing.", value: Binding(get: { workspace.preferences.showFullAddress }, set: { workspace.preferences.showFullAddress = $0 }))
        }
    }
}
