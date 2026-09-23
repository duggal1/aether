import SwiftUI

public struct PasswordsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @BrowserState private var passkeyState: PasskeyAuthorizationState = .unavailable
    @BrowserState private var deviceConfigured = false
    @BrowserState private var localAuthAvailable = false
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        AetherSection("Passkeys") {
            AetherRow("Apple Passwords", symbol: "key") {
                HStack(spacing: 9) {
                    Text(passkeyState.label)
                        .font(AetherType.body(12))
                        .foregroundStyle(passkeyState == .denied ? theme.error : theme.muted)
                    if passkeyState == .notDetermined {
                        Button("Allow Access") { requestPasskey() }
                            .aetherButton()
                    }
                }
            }
            SettingsDivider()
            AetherRow("Device passkey ready", symbol: "checkmark.shield") {
                Text(deviceConfigured ? "Yes" : "No")
                    .font(AetherType.body(12))
                    .foregroundStyle(theme.muted)
            }
            SettingsDivider()
            AetherRow("Device authentication available", symbol: "lock.shield") {
                Text(localAuthAvailable ? "Yes" : "No")
                    .font(AetherType.body(12))
                    .foregroundStyle(theme.muted)
            }
        }
        AetherSection("Passwords") {
            AetherRow("Password autofill", symbol: "key.horizontal") {
                Text("Engine integration required").font(AetherType.body(11)).foregroundStyle(theme.muted)
            }
            SettingsDivider()
            AetherRow("Saved passwords", symbol: "lock") {
                Text("Not connected").font(AetherType.body(11)).foregroundStyle(theme.muted)
            }
        }
        AetherSection("WebAuthn") {
            AetherRow("Website challenges", symbol: "person.crop.circle.badge.checkmark") {
                Text("System flow")
                    .font(AetherType.body(11)).foregroundStyle(theme.muted)
            }
        }
        .onAppear { refreshPasskeyState() }
    }

    private func refreshPasskeyState() {
        guard let capability = workspace.engine as? any BrowserPasskeyCapability else {
            passkeyState = .unavailable
            deviceConfigured = false
            localAuthAvailable = false
            return
        }
        deviceConfigured = capability.passkeyDeviceConfigured
        localAuthAvailable = capability.passkeyLocalAuthAvailable
        passkeyState = capability.passkeyAuthorizationState()
    }

    private func requestPasskey() {
        guard let capability = workspace.engine as? any BrowserPasskeyCapability else { return }
        Task { passkeyState = await capability.requestPasskeyAuthorization() }
    }
}
