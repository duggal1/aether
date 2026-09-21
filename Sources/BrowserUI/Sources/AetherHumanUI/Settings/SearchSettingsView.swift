import SwiftUI

public struct SearchSettingsView: View {
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        AetherSection("Provider") {
            AetherRow("Search provider", symbol: "magnifyingglass") {
                AetherDropdown(
                    selection: Binding(get: { workspace.preferences.provider }, set: { workspace.preferences.provider = $0 }),
                    options: SearchProvider.allCases.map { AetherDropdownOption(value: $0, title: $0.rawValue, iconURL: $0.homepage.absoluteString) },
                    help: "Choose the default search provider",
                    label: "Default search provider")
            }
        }
        AetherSection("Address bar") {
            SettingsToggle("Show full website address", subtitle: "Keep the complete URL visible outside editing.", value: Binding(get: { workspace.preferences.showFullAddress }, set: { workspace.preferences.showFullAddress = $0 }))
            SettingsToggle("Show suggestions while typing", subtitle: "Open tabs, bookmarks, and history appear under the address field.", value: Binding(get: { workspace.preferences.showSearchSuggestions }, set: { workspace.preferences.showSearchSuggestions = $0 }))
            SettingsToggle("Suggestions from \(workspace.preferences.provider.searchName)", subtitle: "Completions are fetched over a private connection; nothing typed is stored.", value: Binding(get: { workspace.preferences.providerSuggestions }, set: { workspace.preferences.providerSuggestions = $0 }))
        }
    }
}
