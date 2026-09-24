import SwiftUI

public struct SettingsSidebarView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Namespace private var glassNamespace
    @Binding var selection: SettingsSection
    public init(selection: Binding<SettingsSection>) { _selection = selection }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Aether")
                .font(AetherType.emphasis(14))
                .foregroundStyle(theme.heading)
                .padding(.horizontal, 11).padding(.top, 26).padding(.bottom, 21)
            ScrollView(.vertical, showsIndicators: false) {
                GlassEffectContainer(spacing: 4) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(SettingsSection.allCases) { section in
                            settingsRow(section)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollClipDisabled(false)
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 14)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.dark
            ? Color(.sRGB, red: 0x1C / 255, green: 0x1C / 255, blue: 0x1C / 255, opacity: 0.35)
            : Color.white.opacity(0.30))
    }

    private func settingsRow(_ section: SettingsSection) -> some View {
        SettingsSidebarRow(section: section, selected: selection == section, namespace: glassNamespace) {
            withAnimation(AetherMotion.snappy(reduced)) { selection = section }
        }
        .animation(AetherMotion.selection(reduced), value: selection)
    }

    private func nativeIcon(for section: SettingsSection) -> AetherSymbol {
        switch section {
        case .general: .settings
        case .tabs: .tabLayout
        case .profiles: .profiles
        case .search: .search
        case .searchIntelligence: .automation
        case .privacy: .privacy
        case .passwords: .passwords
        case .downloads: .download
        case .appearance: .appearance
        case .shortcuts: .shortcuts
        case .advanced: .advanced
        case .networkPrivacy: .network
        case .searchLocation: .location
        }
    }
}

private struct SettingsSidebarRow: View {
    @Environment(\.aetherTheme) private var theme
    @State private var hovering = false
    let section: SettingsSection
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                rowIcon
                Text(section.rawValue).font(AetherType.emphasis(13)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? theme.ink : theme.muted)
            .padding(.horizontal, 12).frame(height: 37)
            .background {
                ZStack {
                    if !selected {
                        RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous)
                            .fill(theme.dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05))
                            .opacity(hovering ? 1 : 0)
                    }
                    if selected {
                        let shape = RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous)
                        shape.fill(.clear)
                            .glassEffect(.regular.tint(theme.dark ? Color.black.opacity(0.18) : Color.white.opacity(0.20)), in: shape)
                            .glassEffectID("settings.selection", in: namespace)
                            .glassEffectTransition(.matchedGeometry)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aetherFocusTreatment(radius: 6)
        .focusEffectDisabled()
        .aetherPointingCursor()
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 }
    }
    @ViewBuilder private var rowIcon: some View {
        let tint = selected ? theme.ink : theme.muted
        Image(systemName: nativeIcon.rawValue)
            .font(AetherType.symbol(16))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 20)
    }
    private var nativeIcon: AetherSymbol {
        switch section {
        case .general: .settings
        case .tabs: .tabLayout
        case .profiles: .profiles
        case .search: .search
        case .searchIntelligence: .automation
        case .privacy: .privacy
        case .passwords: .passwords
        case .downloads: .download
        case .appearance: .appearance
        case .shortcuts: .shortcuts
        case .advanced: .advanced
        case .networkPrivacy: .network
        case .searchLocation: .location
        }
    }
}
