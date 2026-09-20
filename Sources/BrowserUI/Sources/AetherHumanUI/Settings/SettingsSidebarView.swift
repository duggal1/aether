import SwiftUI

public struct SettingsSidebarView: View {
    @Environment(\.aetherTheme) private var theme
    @Binding var selection: SettingsSection
    public init(selection: Binding<SettingsSection>) { _selection = selection }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AetherLogo()
                    .frame(width: 16, height: 16)
                Text("Aether").font(AetherType.body(14))
            }
            .foregroundStyle(theme.heading)
            .padding(.horizontal, 12).padding(.top, 24).padding(.bottom, 24)
            ForEach(SettingsSection.allCases) { section in
                Button { selection = section } label: {
                    HStack(spacing: 11) {
                        AetherSymbolView(nativeIcon(for: section), tint: selection == section ? theme.ink : theme.muted, size: 12)
                            .frame(width: 17)
                        Text(section.rawValue).font(AetherType.body(12)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selection == section ? theme.ink : theme.muted)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(selection == section ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .aetherFocusTreatment(radius: 7)
                .focusEffectDisabled()
                .aetherPointingCursor()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.canvas)
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
