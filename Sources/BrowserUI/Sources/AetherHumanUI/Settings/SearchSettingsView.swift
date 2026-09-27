import SwiftUI

public struct SearchSettingsView: View {
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Provider")
            SettingsCard {
                SettingsRow("Search provider", symbol: "magnifyingglass") {
                    AetherDropdown(
                        selection: Binding(get: { workspace.preferences.provider }, set: { workspace.preferences.provider = $0 }),
                        options: SearchProvider.allCases.map { AetherDropdownOption(value: $0, title: $0.rawValue, iconURL: $0.homepage.absoluteString) },
                        help: "Choose the default search provider",
                        label: "Default search provider")
                }
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Custom engine")
            SettingsCard {
                SettingsRow("Custom template (%s)", symbol: "gearshape") {
                    AetherField("https://example.com/search?q=%s",
                        text: Binding(get: { workspace.preferences.customSearchTemplate },
                                      set: { workspace.preferences.customSearchTemplate = $0 }))
                        .frame(width: 260)
                }
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Address bar")
            SettingsCard {
                SettingsSwitchRow("Show full website address", symbol: "link",
                                  value: Binding(get: { workspace.preferences.showFullAddress }, set: { workspace.preferences.showFullAddress = $0 }))
                SettingsDivider()
                SettingsSwitchRow("Show suggestions while typing", symbol: "magnifyingglass",
                                  value: Binding(get: { workspace.preferences.showSearchSuggestions }, set: { workspace.preferences.showSearchSuggestions = $0 }))
                SettingsDivider()
                SettingsSwitchRow("Suggestions from \(workspace.preferences.provider.searchName)", symbol: "magnifyingglass.circle",
                                  value: Binding(get: { workspace.preferences.providerSuggestions }, set: { workspace.preferences.providerSuggestions = $0 }))
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("System search")
            SettingsCard {
                SettingsSwitchRow("Show saved pages in Spotlight", value: Binding(
                    get: { workspace.preferences.spotlightSavedPages },
                    set: { workspace.setSpotlightSavedPages($0) }))
            }
        }
    }
}

public struct SearchIntelligenceSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    private var skin: AetherSurfaceStyle {
        if let surface, !surface.isHomepage { return surface }
        return AetherSurfaceResolver.style(theme.dark ? .darkWebsite : .lightWebsite,
                                            darkHomepage: theme.dark)
    }

    /// API key wells sit one step darker than the card so the secure fields
    /// read as inset wells on the frost.
    private func darkWell<Content: View>(_ content: Content) -> some View {
        content.background(
            (skin.isDark ? Color.black.opacity(0.16) : Color.black.opacity(0.05)),
            in: RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Search Intelligence")
            SettingsCard {
                SettingsRow("TypeSafe API Key", symbol: "key.horizontal") {
                    darkWell(
                        AetherField("TypeSafe API Key",
                                    text: Binding(get: { workspace.preferences.typeSafeAPIKey },
                                                  set: {
                                                      workspace.preferences.typeSafeAPIKey = $0
                                                      Task { await workspace.syncSearchKeysToEngine() }
                                                  }),
                                    secure: true)
                            .frame(width: 210)
                    )
                }
                SettingsDivider()
                SettingsRow("Search1API Key", symbol: "key.horizontal") {
                    darkWell(
                        AetherField("Search1API Key",
                                    text: Binding(get: { workspace.preferences.search1APIKey },
                                                  set: {
                                                      workspace.preferences.search1APIKey = $0
                                                      Task { await workspace.syncSearchKeysToEngine() }
                                                  }),
                                    secure: true)
                            .frame(width: 210)
                    )
                }
            }
        }
    }
}
