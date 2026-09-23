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
            SettingsToggle("Show full website address", value: Binding(get: { workspace.preferences.showFullAddress }, set: { workspace.preferences.showFullAddress = $0 }))
            SettingsToggle("Show suggestions while typing", value: Binding(get: { workspace.preferences.showSearchSuggestions }, set: { workspace.preferences.showSearchSuggestions = $0 }))
            SettingsToggle("Suggestions from \(workspace.preferences.provider.searchName)", value: Binding(get: { workspace.preferences.providerSuggestions }, set: { workspace.preferences.providerSuggestions = $0 }))
        }
        AetherSection("System search") {
            SettingsToggle("Show saved pages in Spotlight", value: Binding(
                get: { workspace.preferences.spotlightSavedPages },
                set: { workspace.setSpotlightSavedPages($0) }))
        }
    }
}

public struct SearchIntelligenceSettingsView: View {
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    public var body: some View {
        AetherSection("Search Intelligence") {
            AetherRow("TypeSafe API Key", symbol: "key.horizontal") {
                AetherField("TypeSafe API Key",
                            text: Binding(get: { workspace.preferences.typeSafeAPIKey },
                                          set: {
                                              workspace.preferences.typeSafeAPIKey = $0
                                              Task { await workspace.syncSearchKeysToEngine() }
                                          }),
                            secure: true)
                    .frame(width: 210)
            }
            SettingsDivider()
            AetherRow("Search1API Key", symbol: "key.horizontal") {
                AetherField("Search1API Key",
                            text: Binding(get: { workspace.preferences.search1APIKey },
                                          set: {
                                              workspace.preferences.search1APIKey = $0
                                              Task { await workspace.syncSearchKeysToEngine() }
                                          }),
                            secure: true)
                    .frame(width: 210)
            }
        }
    }
}
