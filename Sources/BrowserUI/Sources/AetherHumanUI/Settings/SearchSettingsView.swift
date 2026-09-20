import SwiftUI

public struct SearchSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        SettingsHelp("Aether uses one address field for website addresses and searches.")
        AetherSection("Search engine") {
            AetherRow("Default provider", subtitle: "Searches from the address bar use this provider.", symbol: "magnifyingglass") {
                Picker("Search engine", selection: Binding(get: { workspace.preferences.provider }, set: { workspace.preferences.provider = $0 })) {
                    ForEach(SearchProvider.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 150)
            }
        }
        AetherSection("Address bar") {
            SettingsToggle("Show full website address", subtitle: "Keep the complete URL visible outside editing.", value: Binding(get: { workspace.preferences.showFullAddress }, set: { workspace.preferences.showFullAddress = $0 }))
        }
    }
}
