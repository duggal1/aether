import AppKit
import SwiftUI

public struct PasswordsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @BrowserState private var passkeyState: PasskeyAuthorizationState = .unavailable
    @BrowserState private var deviceConfigured = false
    @BrowserState private var localAuthAvailable = false
    @State private var savedCredentials: [BrowserCredentialSummary] = []
    /// The passwords on screen right now, by credential. A Mac that has said
    /// who is asking has earned them; nothing else puts one here, and closing
    /// the pane or reloading the list takes them away again.
    @State private var shownPasswords: [String: String] = [:]
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
                SettingsRow("Import from Chrome", symbol: "square.and.arrow.down") {
                    Button("Choose File…") { beginImport() }
                        .buttonStyle(AetherLightActionButtonStyle())
                        .focusEffectDisabled()
                        .aetherPointingCursor()
                }
                SettingsDivider()
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
                                if let password = shownPasswords[item.id] {
                                    Text(password)
                                        .font(AetherType.body(11).monospaced())
                                        .foregroundStyle(skin.secondaryText)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                    rowAction("Copy") { copyPassword(item, password) }
                                    rowAction("Hide") { shownPasswords[item.id] = nil }
                                } else {
                                    rowAction("Show") { reveal(item) }
                                }
                                rowAction("Remove") { removeCredential(item) }
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
                shownPasswords = [:]
            } catch {
                credentialError = error.localizedDescription
            }
        }
    }

    private func rowAction(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(title, action: run)
            .buttonStyle(.plain)
            .font(AetherType.body(12))
            .foregroundStyle(skin.secondaryText)
            .aetherPointingCursor()
            .focusEffectDisabled()
    }

    /// A saved password goes on the screen only after the Mac has said who is
    /// asking — Touch ID, the watch, or the account password. Filling a form is
    /// a different thing and asks nothing: there the secret stays in the engine.
    private func reveal(_ credential: BrowserCredentialSummary) {
        guard let provider = workspace.engine as? any BrowserCredentialVaultProviding else { return }
        Task {
            guard await AetherLocalAuth.prove("show the saved password for \(hostTitle(credential))") else { return }
            do {
                shownPasswords[credential.id] = try await provider.savedPassword(
                    profileID: credential.profileID, credentialID: credential.id)
            } catch {
                credentialError = error.localizedDescription
            }
        }
    }

    /// The clipboard is read by anything running on this Mac, so it is filled
    /// only for the person the Mac belongs to, and asked for again every time.
    private func copyPassword(_ credential: BrowserCredentialSummary, _ password: String) {
        Task {
            guard await AetherLocalAuth.prove("copy the saved password for \(hostTitle(credential))") else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(password, forType: .string)
        }
    }

    private func hostTitle(_ credential: BrowserCredentialSummary) -> String {
        URL(string: credential.origin)?.host ?? credential.origin
    }

    /// A file of passwords comes in as one act, so it is one proof: the Mac is
    /// asked once, before anything is written, and the report says what landed.
    /// The same rule as a password saved from a page holds row by row — the
    /// vault decides what it will keep, and a row it refuses is counted, not
    /// written somewhere else.
    private func beginImport() {
        guard let provider = workspace.engine as? any BrowserCredentialVaultProviding,
              let profile = workspace.profiles.first(where: { !$0.isIncognito }),
              let picked = CredentialTransfer.pick() else { return }
        guard !picked.credentials.isEmpty else {
            credentialError = picked.skipped > 0
                ? "No passwords could be read from that file."
                : "That file has no passwords in it."
            return
        }
        Task {
            guard await AetherLocalAuth.prove(
                "import \(picked.credentials.count) passwords into Aether") else { return }
            var kept = 0
            var refused = 0
            for credential in picked.credentials {
                do {
                    try await provider.saveCredential(
                        profileID: profile.id, origin: credential.origin,
                        username: credential.username, password: credential.password)
                    kept += 1
                } catch {
                    refused += 1
                }
            }
            refreshSavedCredentials()
            let skipped = picked.skipped + refused
            credentialError = skipped > 0
                ? "Imported \(kept) passwords. \(skipped) rows could not be imported."
                : "Imported \(kept) passwords."
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
