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

    /// Cards read this: the blur recipe + white text in dark mode, resolved
    /// from the settings window's own scheme — never the page behind it.
    private var surfaceStyle: AetherSurfaceStyle {
        AetherSurfaceResolver.style(settingsScheme == .dark ? .darkWebsite : .lightWebsite,
                                    darkHomepage: settingsScheme == .dark)
    }

    public var body: some View {
        HStack(spacing: 0) {
            SettingsSidebarView(selection: $selection)
                .frame(width: AetherMetrics.settingsSidebar)
            Rectangle()
                .fill(theme.dark ? Color.white.opacity(0.06) : Color.black.opacity(0.08))
                .frame(width: 0.5)
            VStack(alignment: .leading, spacing: 0) {
                Text(selection.rawValue)
                    .font(AetherType.panelTitle(23)).tracking(AetherTracking.heading)
                    .foregroundStyle(theme.textStrong)
                    .padding(.horizontal, 26)
                    .padding(.top, 26)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("title-\(selection)")
                    .transition(AetherMotion.blurInOut(reduced))

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
                    }
                    .frame(maxHeight: .infinity)
                    .scrollClipDisabled(false)
                    .onChange(of: selection) { _, _ in
                        withAnimation(AetherMotion.container(reduced)) {
                            proxy.scrollTo("settingsTop", anchor: .top)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
        }
        .frame(width: 800, height: 550)
        .background { SettingsWindowBlurBackground() }
        .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.panelRadius, style: .continuous))
        // Transparent sheet so the behind-window frost has the dimmed browser
        // to refract — an opaque sheet window is what flattened every blur.
        .presentationBackground(.clear)
        .toggleStyle(.switch)
        .controlSize(.regular)
        .aetherTypography()
        .environment(\.colorScheme, settingsScheme)
        .environment(\.aetherTheme, theme)
        // The settings window's card and sidebar follow its own resolved scheme,
        // never the scheme of the page that happens to be open behind it.
        .environment(\.aetherChromeAppearance, settingsScheme == .dark ? .dark : .light)
        .environment(\.aetherSurfaceStyle, surfaceStyle)
        .preferredColorScheme(workspace.preferences.appearance.colorScheme)
        .animation(AetherMotion.container(reduced), value: selection)
    }

    @ViewBuilder private var sectionContent: some View {
        switch selection {
        case .general: GeneralSettingsView(workspace: workspace)
        case .tabs: TabsSettingsView(workspace: workspace)
        case .profiles: ProfilesSettingsView(workspace: workspace)
        case .extensions: ExtensionsSettingsView(workspace: workspace)
        case .search: SearchSettingsView(workspace: workspace)
        case .searchIntelligence: SearchIntelligenceSettingsView(workspace: workspace)
        case .privacy: PrivacySettingsView(workspace: workspace)
        case .passwords: PasswordsSettingsView(workspace: workspace)
        case .downloads: DownloadsSettingsView(workspace: workspace)
        case .appearance: AppearanceSettingsView(workspace: workspace)
        case .shortcuts: ShortcutsSettingsView()
        }
    }
}
