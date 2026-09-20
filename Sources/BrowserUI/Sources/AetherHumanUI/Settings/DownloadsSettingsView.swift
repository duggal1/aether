import SwiftUI

public struct DownloadsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        SettingsHelp("Choose the display preference for completed downloads. Actual transfers and destination permissions must be handled by Aether's engine.")
        AetherSection("Destination") {
            AetherRow("Folder", subtitle: "Preferred download folder label.", symbol: "folder") {
                Text("Engine integration required").font(AetherType.body(11)).foregroundStyle(theme.muted)
            }
        }
        SettingsHelp("The folder label alone does not grant file-system access or change Aether's actual download destination.")
    }
}
