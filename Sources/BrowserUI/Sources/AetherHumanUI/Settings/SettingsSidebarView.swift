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
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(SettingsSection.allCases) { section in
                        settingsRow(section)
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
        // Sidebar tone, not a second card.
        .background(theme.dark ? Color.white.opacity(0.035) : Color.black.opacity(0.025))
    }

    private func settingsRow(_ section: SettingsSection) -> some View {
        SettingsSidebarRow(section: section, selected: selection == section) {
            withAnimation(AetherMotion.snappy(reduced)) { selection = section }
        }
        .animation(AetherMotion.selection(reduced), value: selection)
    }
}

private struct SettingsSidebarRow: View {
    @Environment(\.aetherTheme) private var theme
    @State private var hovering = false
    let section: SettingsSection
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(AetherType.symbol(16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected
                                     ? (theme.dark ? Color.white : theme.ink)
                                     : (theme.dark ? Color.white.opacity(0.72) : theme.muted))
                    .frame(width: 20)
                    .accessibilityHidden(true)
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
                        // The settings sidebar is a sidebar, so its selection uses
                        // the same one glass state as the browser sidebar.
                        let shape = RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous)
                        shape.fill(.clear)
                            .glassEffect(.regular.tint(theme.dark ? Color.black.opacity(0.20)
                                                                   : Color.white.opacity(0.35)), in: shape)
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
}
