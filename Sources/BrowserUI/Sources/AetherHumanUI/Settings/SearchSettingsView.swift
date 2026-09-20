import SwiftUI

public struct SearchSettingsView: View {
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        SettingsHelp("Aether uses one address field for website addresses and searches.")
        AetherSection("Search engine") {
            AetherRow("Default provider", subtitle: "Searches from the address bar use this provider.", symbol: "magnifyingglass") {
                Picker("Default search provider", selection: Binding(get: { workspace.preferences.provider }, set: { workspace.preferences.provider = $0 })) {
                    ForEach(SearchProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
                .help("Choose the default search provider")
                .accessibilityLabel("Default search provider")
            }
        }
        AetherSection("Address bar") {
            SettingsToggle("Show full website address", subtitle: "Keep the complete URL visible outside editing.", value: Binding(get: { workspace.preferences.showFullAddress }, set: { workspace.preferences.showFullAddress = $0 }))
        }
    }
}
