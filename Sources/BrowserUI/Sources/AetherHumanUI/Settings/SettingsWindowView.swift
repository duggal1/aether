import SwiftUI

public struct SettingsWindowView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var selection: SettingsSection = .general
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    public var body: some View {
        HStack(spacing: 0) {
            SettingsSidebarView(selection: $selection)
                .frame(width: AetherMetrics.settingsSidebar)
            Rectangle()
                .fill(theme.control)
                .frame(width: 0.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(selection.rawValue)
                        .font(AetherType.emphasis(19)).foregroundStyle(theme.heading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) { sectionContent }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 28).padding(.bottom, 30)
                        .id(selection)
                        .transition(AetherMotion.contentSwap(reduced))
                }
                .animation(AetherMotion.snappy(reduced), value: selection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.settingsCanvas)
        }
        .frame(width: 820, height: 570)
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.menuRadius, style: .continuous))
        .toggleStyle(.switch)
        .controlSize(.regular)
        .tint(.accentColor)
        .aetherTypography()
        .aetherDarkGlassShadow(dark: theme.dark)
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
