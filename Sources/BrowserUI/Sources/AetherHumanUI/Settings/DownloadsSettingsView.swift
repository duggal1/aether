import SwiftUI

public struct DownloadsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        AetherSection("Destination") {
            AetherRow("Folder", customIcon: .cloudDownload) {
                Text("Engine integration required").font(AetherType.body(11)).foregroundStyle(theme.muted)
            }
        }
    }
}
