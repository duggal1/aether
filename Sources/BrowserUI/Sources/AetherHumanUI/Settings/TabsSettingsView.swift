import SwiftUI

public struct TabsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    public var body: some View {
        SettingsHelp("Change the location of your tabs. Existing pages and browser sessions stay intact.")
        AetherSection("Tab layout") {
            HStack(spacing: 13) {
                layoutCard(.top)
                layoutCard(.sidebar)
            }
            .padding(12)
        }
        if workspace.preferences.arrangement == .sidebar {
            AetherSection("Sidebar") {
                AetherRow("Sidebar width", subtitle: "Drag or adjust the preferred width.") {
                    Slider(value: Binding(get: { workspace.preferences.sidebarWidth },
                                          set: { workspace.preferences.sidebarWidth = $0 }), in: 188...324)
                        .frame(width: 170)
                    Text("\(Int(workspace.preferences.sidebarWidth)) pt")
                        .font(AetherType.mono(11)).foregroundStyle(theme.muted)
                        .frame(width: 46, alignment: .trailing)
                }
                SettingsDivider()
                SettingsToggle("Pinned favorites in sidebar",
                               value: Binding(get: { workspace.preferences.showFavorites },
                                              set: { workspace.preferences.showFavorites = $0 }))
            }
        }
    }

    private func layoutCard(_ mode: TabArrangement) -> some View {
        let selected = workspace.preferences.arrangement == mode
        return Button { workspace.preferences.arrangement = mode } label: {
            VStack(alignment: .leading, spacing: 11) {
                layoutIllustration(mode)
                HStack {
                    Text(mode == .top ? "Top of Window" : "Sidebar").font(AetherType.rowTitle(12))
                    Spacer(minLength: 6)
                    Image(systemName: selected ? AetherSymbol.selected.rawValue : AetherSymbol.unselected.rawValue)
                        .font(AetherType.symbol(12))
                        .foregroundStyle(selected ? theme.ink : theme.soft)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(selected ? theme.settingsRaised : theme.canvas,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .focusEffectDisabled()
        .foregroundStyle(theme.ink)
    }

    private func layoutIllustration(_ mode: TabArrangement) -> some View {
        VStack(spacing: 4) {
            if mode == .top {
                HStack(spacing: 4) {
                    Capsule().fill(theme.muted).frame(width: 33, height: 6)
                    Capsule().fill(theme.soft.opacity(0.5)).frame(width: 33, height: 6)
                    Spacer()
                }
                Capsule().fill(theme.soft.opacity(0.4)).frame(height: 4)
                RoundedRectangle(cornerRadius: 3).fill(theme.surface).frame(height: 39)
            } else {
                HStack(spacing: 5) {
                    VStack(spacing: 5) {
                        Capsule().fill(theme.muted).frame(height: 4)
                        Capsule().fill(theme.soft.opacity(0.4)).frame(height: 4)
                        Capsule().fill(theme.soft.opacity(0.4)).frame(height: 4)
                        Spacer()
                    }
                    .frame(width: 35)
                    RoundedRectangle(cornerRadius: 1).fill(theme.soft.opacity(0.25)).frame(width: 1)
                    VStack(spacing: 5) {
                        Capsule().fill(theme.soft.opacity(0.4)).frame(height: 4)
                        RoundedRectangle(cornerRadius: 3).fill(theme.surface).frame(height: 39)
                    }
                }
            }
        }
        .padding(10)
        .frame(height: 66)
        .background(theme.inset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
