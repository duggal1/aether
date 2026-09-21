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
                .frame(width: 208)
            Rectangle().fill(theme.hairline).frame(width: 0.5)
            VStack(alignment: .leading, spacing: 0) {
                Text(selection.rawValue)
                    .font(AetherType.panelTitle(23))
                    .foregroundStyle(theme.textStrong)
                    .padding(.horizontal, 26)
                    .padding(.top, 26)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView {
                    VStack(alignment: .leading, spacing: 23) { sectionContent }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 26)
                        .padding(.bottom, 30)
                        .id(selection)
                        .transition(AetherMotion.contentSwap(reduced))
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.background)
        }
        .frame(width: 800, height: 550)
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .toggleStyle(.switch)
        .controlSize(.regular)
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
