import SwiftUI

public struct SettingsSidebarView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Binding var selection: SettingsSection
    public init(selection: Binding<SettingsSection>) { _selection = selection }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Aether")
                .font(AetherType.emphasis(14))
                .foregroundStyle(theme.heading)
                .padding(.horizontal, 11).padding(.top, 26).padding(.bottom, 21)
            ForEach(SettingsSection.allCases) { section in
                settingsRow(section)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.chrome)
    }

    private func settingsRow(_ section: SettingsSection) -> some View {
        Button {
            withAnimation(AetherMotion.snappy(reduced)) { selection = section }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: nativeIcon(for: section).rawValue)
                    .font(AetherType.symbol(16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selection == section ? theme.ink : theme.muted)
                    .frame(width: 20)
                Text(section.rawValue).font(AetherType.emphasis(13)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selection == section ? theme.ink : theme.muted)
            .padding(.horizontal, 12).frame(height: 37)
            .background {
                if selection == section {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(theme.hover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aetherFocusTreatment(radius: 6)
        .focusEffectDisabled()
        .aetherPointingCursor()
        .accessibilityAddTraits(selection == section ? .isSelected : [])
        .animation(AetherMotion.selection(reduced), value: selection)
    }

    private func nativeIcon(for section: SettingsSection) -> AetherSymbol {
        switch section {
        case .general: .settings
        case .tabs: .tabLayout
        case .profiles: .profiles
        case .search: .search
        case .privacy: .privacy
        case .passwords: .passwords
        case .downloads: .download
        case .appearance: .appearance
        case .shortcuts: .shortcuts
        case .advanced: .advanced
        }
    }
}
