import SwiftUI

public struct SettingsWindowView: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var selection: SettingsSection = .general
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    private var settingsScheme: ColorScheme {
        workspace.preferences.appearance.colorScheme ?? systemScheme
    }

    private var theme: AetherTheme { AetherTheme(settingsScheme) }

    public var body: some View {
        HStack(spacing: 0) {
            SettingsSidebarView(selection: $selection)
                .frame(width: AetherMetrics.settingsSidebar)
            Rectangle().fill(theme.hairline.opacity(0.06)).frame(width: 0.5)
            VStack(alignment: .leading, spacing: 0) {
                Text(selection.rawValue)
                    .font(AetherType.panelTitle(23)).tracking(AetherTracking.heading)
                    .foregroundStyle(theme.textStrong)
                    .padding(.horizontal, 26)
                    .padding(.top, 26)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 16) {
                            Color.clear.frame(height: 0).id("settingsTop")
                            sectionContent
                            Color.clear.frame(height: 12)
                        }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 26)
                            .padding(.top, 2)
                            .padding(.bottom, 44)
                            .id(selection)
                            .transition(AetherMotion.contentSwap(reduced))
                    }
                    .frame(maxHeight: .infinity)
                    .scrollClipDisabled(false)
                    .onChange(of: selection) { _, _ in
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("settingsTop", anchor: .top) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background)
        }
        .frame(width: 800, height: 550)
        .background(theme.background)
        .toggleStyle(.switch)
        .controlSize(.regular)
        .aetherTypography()
        .environment(\.colorScheme, settingsScheme)
        .environment(\.aetherTheme, theme)
        .preferredColorScheme(workspace.preferences.appearance.colorScheme)
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.panelRadius, style: .continuous))
    }

    @ViewBuilder private var sectionContent: some View {
        switch selection {
        case .general: GeneralSettingsView(workspace: workspace)
        case .tabs: TabsSettingsView(workspace: workspace)
        case .profiles: ProfilesSettingsView(workspace: workspace)
        case .search: SearchSettingsView(workspace: workspace)
        case .searchIntelligence: SearchIntelligenceSettingsView(workspace: workspace)
        case .privacy: PrivacySettingsView(workspace: workspace)
        case .passwords: PasswordsSettingsView(workspace: workspace)
        case .downloads: DownloadsSettingsView(workspace: workspace)
        case .appearance: AppearanceSettingsView(workspace: workspace)
        case .shortcuts: ShortcutsSettingsView()
        case .advanced: AdvancedSettingsView(workspace: workspace)
        case .networkPrivacy: NetworkSettingsView(workspace: workspace)
        case .searchLocation: SearchLocationSettingsView(workspace: workspace)
        }
    }
}
