import SwiftUI

public struct AdvancedSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        AetherSection("Runtime") {
            AetherRow("Engine connection", symbol: "cpu") {
                if workspace.engine.isConnected {
                    AetherBadge("Connected", variant: .green)
                } else {
                    Text("Not connected")
                        .font(AetherType.body(12))
                        .foregroundStyle(theme.muted)
                }
            }
            SettingsDivider()
            AetherRow("Browser engine", customIcon: .engine) {
                Text("Aether").font(AetherType.data(11)).foregroundStyle(theme.muted)
            }
        }
        AetherSection("Developer tools") {
            AetherRow("Page inspection", customIcon: .inspect) {
                EmptyView()
            }
        }
    }
}
