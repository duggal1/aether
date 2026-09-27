import SwiftUI

public struct DownloadsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    private var skin: AetherSurfaceStyle {
        if let surface, !surface.isHomepage { return surface }
        return AetherSurfaceResolver.style(theme.dark ? .darkWebsite : .lightWebsite,
                                            darkHomepage: theme.dark)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Destination")
            SettingsCard {
                SettingsRow("Folder", symbol: "arrow.down.circle") {
                    Text(workspace.preferences.downloadFolder).font(AetherType.body(12)).foregroundStyle(skin.primaryText)
                }
                SettingsDivider()
                SettingsSwitchRow("Ask where to save each file", symbol: "questionmark.circle",
                    value: Binding(get: { workspace.preferences.askWhereOnDownload }, set: { workspace.preferences.askWhereOnDownload = $0 }))
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Behavior")
            SettingsCard {
                Text("When Ask is on, the engine save panel appears before writing to \(workspace.preferences.downloadFolder).")
                    .font(AetherType.body(11)).foregroundStyle(skin.secondaryText)
            }
        }
    }
}
