import SwiftUI

public struct TabsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduced
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    private var skin: AetherSurfaceStyle {
        if let surface, !surface.isHomepage { return surface }
        return AetherSurfaceResolver.style(theme.dark ? .darkWebsite : .lightWebsite,
                                            darkHomepage: theme.dark)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Tab layout")
            SettingsCard {
                HStack(spacing: 12) {
                    layoutCard(.top)
                    layoutCard(.sidebar)
                }
                .padding(12)
            }
        }
        if workspace.preferences.arrangement == .sidebar {
            VStack(alignment: .leading, spacing: 9) {
                SettingsHeader("Sidebar")
                SettingsCard {
                    SettingsRow("Sidebar width", symbol: "sidebar.left") {
                        HStack(spacing: 10) {
                            Slider(value: Binding(get: { workspace.preferences.sidebarWidth },
                                                  set: { workspace.preferences.sidebarWidth = $0 }), in: 188...324)
                                .frame(width: 150)
                            Text("\(Int(workspace.preferences.sidebarWidth)) pt")
                                .font(AetherType.data(11)).foregroundStyle(skin.secondaryText)
                                .frame(width: 46, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }
                    SettingsDivider()
                    SettingsSwitchRow("Pinned favorites in sidebar", symbol: "pin",
                                      value: Binding(get: { workspace.preferences.showFavorites },
                                                     set: { workspace.preferences.showFavorites = $0 }))
                }
            }
        }
    }

    private func layoutCard(_ mode: TabArrangement) -> some View {
        let selected = workspace.preferences.arrangement == mode
        return Button { workspace.preferences.arrangement = mode } label: {
            VStack(alignment: .leading, spacing: 10) {
                layoutIllustration(mode, selected: selected)
                HStack(spacing: 6) {
                    Text(mode == .top ? "Top of Window" : "Sidebar")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(skin.primaryText)
                    Spacer(minLength: 6)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selected
                                         ? (skin.isDark ? Color.white : skin.primaryText)
                                         : skin.secondaryIcon)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? skin.selectionFill : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? skin.primaryText.opacity(0.55) : skin.fieldBorder, lineWidth: selected ? 1.25 : 0.5)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .focusEffectDisabled()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Editorial window mock: hairline frame, one confident active pill,
    /// stepped quiet pills, calm content well. Same geometry for both modes.
    private func layoutIllustration(_ mode: TabArrangement, selected: Bool) -> some View {
        let frame = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let active = skin.isDark ? Color.white : skin.primaryText
        return ZStack {
            frame.fill(skin.fieldFill)
            frame.strokeBorder(skin.fieldBorder, lineWidth: 0.5)
            if mode == .top {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Capsule().fill(active).frame(width: 32, height: 5)
                        Capsule().fill(skin.secondaryText.opacity(0.40)).frame(width: 32, height: 5)
                        Capsule().fill(skin.secondaryText.opacity(0.22)).frame(width: 20, height: 5)
                        Spacer(minLength: 0)
                    }
                    Capsule().fill(skin.secondaryText.opacity(0.30)).frame(height: 4)
                        .padding(.horizontal, 2)
                    RoundedRectangle(cornerRadius: 4).fill(skin.controlFill)
                        .frame(height: 36)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4).strokeBorder(skin.fieldBorder, lineWidth: 0.5)
                        }
                }
                .padding(10)
            } else {
                HStack(spacing: 7) {
                    VStack(spacing: 5) {
                        Capsule().fill(active).frame(height: 5)
                        Capsule().fill(skin.secondaryText.opacity(0.40)).frame(height: 5)
                        Capsule().fill(skin.secondaryText.opacity(0.22)).frame(height: 5)
                        Spacer(minLength: 0)
                    }
                    .frame(width: 30)
                    RoundedRectangle(cornerRadius: 1).fill(skin.fieldBorder).frame(width: 0.5)
                    VStack(spacing: 6) {
                        Capsule().fill(skin.secondaryText.opacity(0.30)).frame(height: 4)
                            .padding(.horizontal, 2)
                        RoundedRectangle(cornerRadius: 4).fill(skin.controlFill)
                            .frame(height: 36)
                            .overlay {
                                RoundedRectangle(cornerRadius: 4).strokeBorder(skin.fieldBorder, lineWidth: 0.5)
                            }
                    }
                }
                .padding(10)
            }
        }
        .frame(height: 80)
        .opacity(selected ? 1 : 0.85)
    }
}
