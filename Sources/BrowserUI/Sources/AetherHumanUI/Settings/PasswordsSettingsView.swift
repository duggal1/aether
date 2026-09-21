import SwiftUI

public struct PasswordsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        SettingsHelp("Keychain and passkey access arrive with engine authorization.")
        AetherSection("Passwords") {
            AetherRow("Password autofill", subtitle: "Requires a real Security framework and form integration.", symbol: "key.horizontal") {
                Text("Engine integration required").font(AetherType.body(11)).foregroundStyle(theme.muted)
            }
            SettingsDivider()
            AetherRow("Saved passwords", subtitle: "Never stored in Aether UI preferences.", symbol: "lock") {
                Text("Not connected").font(AetherType.body(11)).foregroundStyle(theme.muted)
            }
        }
        AetherSection("Passkeys") {
            AetherRow("AuthenticationServices", subtitle: "Website WebAuthn challenges require authorized browser credential integration.", symbol: "person.crop.circle.badge.checkmark") {
                Text("Not connected").font(AetherType.body(11)).foregroundStyle(theme.muted)
            }
        }
    }
}
