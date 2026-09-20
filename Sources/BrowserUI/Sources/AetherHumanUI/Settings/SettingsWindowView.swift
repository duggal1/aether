import SwiftUI

public struct SettingsWindowView: View {
    @Environment(\.aetherTheme) private var theme
    @BrowserState private var selection: SettingsSection = .general
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    public var body: some View {
        HStack(spacing: 0) {
            SettingsSidebarView(selection: $selection)
                .frame(width: AetherMetrics.settingsSidebar)
            Rectangle()
                .fill(theme.hairline)
                .frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(selection.rawValue)
                        .font(AetherType.panelTitle(20)).foregroundStyle(theme.heading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 25).padding(.top, 25).padding(.bottom, 18)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) { sectionContent }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 25).padding(.bottom, 30)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.canvas)
        }
        .frame(width: 800, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.panelRadius, style: .continuous))
        .aetherTypography()
        .preferredColorScheme(workspace.preferences.appearance.colorScheme)
    }

    @ViewBuilder private var sectionContent: some View {
        switch selection {
        case .general: GeneralSettingsView(workspace: workspace)
        case .tabs: TabsSettingsView(workspace: workspace)
        case .profiles: ProfilesSettingsView(workspace: workspace)
        case .search: SearchSettingsView(workspace: workspace)
        case .privacy: PrivacySettingsView(workspace: workspace)
        case .passwords: PasswordsSettingsView(workspace: workspace)
        case .downloads: DownloadsSettingsView(workspace: workspace)
        case .appearance: AppearanceSettingsView(workspace: workspace)
        case .shortcuts: ShortcutsSettingsView()
        case .advanced: AdvancedSettingsView(workspace: workspace)
        }
    }
}
