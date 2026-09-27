import SwiftUI

public struct PasswordsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @BrowserState private var passkeyState: PasskeyAuthorizationState = .unavailable
    @BrowserState private var deviceConfigured = false
    @BrowserState private var localAuthAvailable = false
    @State private var savedCredentials: [BrowserCredentialSummary] = []
    @State private var credentialError: String?
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    private var skin: AetherSurfaceStyle {
        if let surface, !surface.isHomepage { return surface }
        return AetherSurfaceResolver.style(theme.dark ? .darkWebsite : .lightWebsite,
                                            darkHomepage: theme.dark)
    }

    /// Title + badge only — no descriptive prose. The badge carries the state.
    private var passkeyBadge: (String, AetherBadgeVariant)? {
        switch passkeyState {
        case .authorized where deviceConfigured && localAuthAvailable: ("Ready", .green)
        case .authorized: ("Connected", .green)
        case .notDetermined: ("Not Set Up", .orange)
        case .denied: ("Denied", .rose)
        case .unavailable: nil
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Passkeys")
            SettingsCard {
                SettingsRow("Apple Passwords", symbol: "key.horizontal") {
                    HStack(spacing: 9) {
                        if let badge = passkeyBadge {
                            AetherBadge(badge.0, variant: badge.1)
                        }
                        if passkeyState == .notDetermined {
                            Button("Allow Access") { requestPasskey() }
                                .buttonStyle(AetherLightActionButtonStyle())
                                .focusEffectDisabled()
                                .aetherPointingCursor()
                        }
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Passwords")
            SettingsCard {
                SettingsRow("Save after successful sign-in", symbol: "key.horizontal") {
                    Text("Keychain").font(AetherType.body(11)).foregroundStyle(skin.secondaryText)
                }
                SettingsDivider()
                SettingsRow("Password suggestions", symbol: "person.text.rectangle") {
                    Text("Exact website only").font(AetherType.body(11)).foregroundStyle(skin.secondaryText)
                }
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Saved passwords")
            SettingsCard {
                if savedCredentials.isEmpty {
                    SettingsRow("No saved passwords", symbol: "lock") {
                        Text("Sign in to a website and choose Save Password.")
                            .font(AetherType.body(11)).foregroundStyle(skin.secondaryText)
                    }
                } else {
                    ForEach(Array(savedCredentials.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { SettingsDivider() }
                        SettingsRow(URL(string: item.origin)?.host ?? item.origin, symbol: "lock") {
                            HStack(spacing: 10) {
                                Text(item.username.isEmpty ? "No username" : item.username)
                                    .font(AetherType.body(11)).foregroundStyle(skin.secondaryText).lineLimit(1)
                                Button("Remove") {
                                    removeCredential(item)
                                }
                                .buttonStyle(.plain)
                                .font(AetherType.body(12))
                                .foregroundStyle(skin.secondaryText)
                                .aetherPointingCursor()
                                .focusEffectDisabled()
                            }
                        }
                    }
                }
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("WebAuthn")
            SettingsCard {
                SettingsRow("Website challenges", symbol: "person.crop.circle.badge.checkmark") {
                    Text("System flow")
                        .font(AetherType.body(11)).foregroundStyle(skin.secondaryText)
                }
            }
        }
        .onAppear { refreshPasskeyState(); refreshSavedCredentials() }
        .onChange(of: workspace.profiles) { _, _ in refreshSavedCredentials() }
        .alert("Aether", isPresented: Binding(
            get: { credentialError != nil }, set: { if !$0 { credentialError = nil } })) {
                Button("OK") { credentialError = nil }
            } message: { Text(credentialError ?? "") }
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

    private func refreshSavedCredentials() {
        guard let provider = workspace.engine as? any BrowserCredentialVaultProviding else {
            savedCredentials = []
            return
        }
        Task {
            do {
                var loaded: [BrowserCredentialSummary] = []
                for profile in workspace.profiles where !profile.isIncognito {
                    loaded += try await provider.savedCredentials(profileID: profile.id, origin: nil)
                }
                savedCredentials = loaded
            } catch {
                credentialError = error.localizedDescription
            }
        }
    }

    private func removeCredential(_ credential: BrowserCredentialSummary) {
        guard let provider = workspace.engine as? any BrowserCredentialVaultProviding else { return }
        Task {
            do {
                try await provider.deleteCredential(
                    profileID: credential.profileID, credentialID: credential.id)
                refreshSavedCredentials()
            } catch {
                credentialError = error.localizedDescription
            }
        }
    }
}
