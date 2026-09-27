import SwiftUI

public struct PrivacySettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @BrowserState private var errorMessage: String?
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    private var skin: AetherSurfaceStyle {
        if let surface, !surface.isHomepage { return surface }
        return AetherSurfaceResolver.style(theme.dark ? .darkWebsite : .lightWebsite,
                                            darkHomepage: theme.dark)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Content blocking")
            SettingsCard {
                SettingsSwitchRow("Block ads", symbol: "hand.raised", value: toggle(\.blockAds))
                SettingsDivider()
                SettingsSwitchRow("Block trackers", symbol: "shield", value: toggle(\.blockTrackers))
                SettingsDivider()
                SettingsSwitchRow("Handle cookie banners", symbol: "cookie", value: toggle(\.handleCookieBanners))
            }
            Text(workspace.engine.isConnected ? "Changes are submitted to the connected engine." : "Preview only. Connect the engine before content blocking can protect actual requests.")
                .font(AetherType.caption(12))
                .foregroundStyle(skin.metadataText)
                .padding(.leading, 2)
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Browsing data")
            SettingsCard {
                SettingsRow("History", symbol: "clock") {
                    Text("Manage from History").font(AetherType.body(11)).foregroundStyle(skin.secondaryText)
                }
            }
        }
        if let errorMessage {
            Text(errorMessage)
                .font(AetherType.body(11))
                .foregroundStyle(AetherPalette.error(skin.isDark))
        }
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
