import SwiftUI

public struct GeneralSettingsView: View {
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("On startup")
            SettingsCard {
                SettingsRow("Restore previous windows", symbol: "power") {
                    Toggle("Restore previous windows", isOn: Binding(get: { workspace.preferences.restoreWindows }, set: { workspace.preferences.restoreWindows = $0 })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Video playback")
            SettingsCard {
                SettingsRow("Float video when switching tabs", symbol: "pip") {
                    Toggle("Float video when switching tabs", isOn: Binding(
                        get: { workspace.preferences.floatVideoWhenSwitchingTabs },
                        set: { workspace.preferences.floatVideoWhenSwitchingTabs = $0 }
                    )).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                SettingsDivider()
                SettingsRow("Float video when switching apps", symbol: "pip.enter") {
                    Toggle("Float video when switching apps", isOn: Binding(
                        get: { workspace.preferences.floatVideoWhenSwitchingApps },
                        set: { workspace.preferences.floatVideoWhenSwitchingApps = $0 }
                    )).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("New windows")
            SettingsCard {
                SettingsRow("Open with profile", symbol: "person.crop.circle") {
                    AetherDropdown(
                        selection: Binding(get: { workspace.defaultProfileID }, set: { workspace.setDefaultProfile($0) }),
                        options: workspace.profiles.map { AetherDropdownOption(value: $0.id, title: $0.name) },
                        help: "Choose the profile for new windows",
                        label: "Open new windows with profile")
                }
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Tabs")
            SettingsCard {
                SettingsSwitchRow("Sleep unused tabs (30 min)", symbol: "moon",
                    value: Binding(get: { workspace.preferences.sleepTabsEnabled }, set: { workspace.preferences.sleepTabsEnabled = $0 }))
                SettingsDivider()
                SettingsSwitchRow("Show bookmarks bar", symbol: "bookmark",
                    value: Binding(get: { workspace.preferences.showBookmarksBar }, set: { workspace.preferences.showBookmarksBar = $0 }))
                SettingsDivider()
                SettingsSwitchRow("Show link destination", symbol: "link",
                    value: Binding(get: { workspace.preferences.showStatusLine }, set: { workspace.preferences.showStatusLine = $0 }))
                SettingsDivider()
                SettingsSwitchRow("Shift-click opens preview", symbol: "eye",
                    value: Binding(get: { workspace.preferences.peekOnShiftClick }, set: { workspace.preferences.peekOnShiftClick = $0 }))
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Downloads")
            SettingsCard {
                SettingsSwitchRow("Ask where to save", symbol: "arrow.down.circle",
                    value: Binding(get: { workspace.preferences.askWhereOnDownload }, set: { workspace.preferences.askWhereOnDownload = $0 }))
            }
        }
    }
}
