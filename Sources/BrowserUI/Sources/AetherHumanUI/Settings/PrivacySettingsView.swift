import SwiftUI

public struct PrivacySettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @BrowserState private var errorMessage: String?
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        AetherSection("Content blocking", footer: workspace.engine.isConnected ? "Changes are submitted to the connected engine." : "Preview only. Connect the engine before content blocking can protect actual requests.") {
            SettingsToggle("Block ads", symbol: "hand.raised", value: toggle(\.blockAds))
            SettingsDivider()
            SettingsToggle("Block trackers", symbol: "shield", value: toggle(\.blockTrackers))
            SettingsDivider()
            SettingsToggle("Handle cookie banners", symbol: "checkmark.shield", value: toggle(\.handleCookieBanners))
        }
        AetherSection("Browsing data") {
            AetherRow("History", symbol: "clock") {
                Text("Manage from History").font(AetherType.body(11)).foregroundStyle(theme.muted)
            }
        }
        if let errorMessage { Text(errorMessage).font(AetherType.body(11)).foregroundStyle(theme.error) }
    }
    private func toggle(_ property: WritableKeyPath<BrowserPrivacyPolicy, Bool>) -> Binding<Bool> {
        Binding(get: { workspace.preferences.privacy[keyPath: property] }, set: { value in
            var policy = workspace.preferences.privacy
            policy[keyPath: property] = value
            workspace.preferences.privacy = policy
            guard workspace.engine.isConnected else { return }
            for profile in workspace.profiles {
                Task {
                    do { try await workspace.engine.updatePrivacy(profileID: profile.id, policy: policy) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
        })
    }
}
