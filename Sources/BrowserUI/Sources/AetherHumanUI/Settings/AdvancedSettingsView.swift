import SwiftUI

public struct AdvancedSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        AetherSection("Runtime") {
            AetherRow("Engine connection", subtitle: "Same runtime for humans and external agents.", symbol: "cpu") {
                Text(workspace.engine.isConnected ? "Connected" : "Not connected")
                    .font(AetherType.medium(11))
                    .foregroundStyle(workspace.engine.isConnected ? theme.active : theme.muted)
            }
            SettingsDivider()
            AetherRow("Browser engine", subtitle: "Custom Swift engine. No WebKit or Chromium wrapper.", symbol: "square.stack.3d.up") {
                Text("Aether").font(AetherType.mono(11)).foregroundStyle(theme.muted)
            }
        }
        AetherSection("Developer tools") {
            AetherRow("Page inspection", subtitle: "Connect DOM and network diagnostics to Aether's engine APIs.", symbol: "chevron.left.forwardslash.chevron.right") {
                Text("Adapter required").font(AetherType.body(11)).foregroundStyle(theme.muted)
            }
        }
    }
}
