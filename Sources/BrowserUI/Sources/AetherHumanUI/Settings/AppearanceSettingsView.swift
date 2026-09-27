import SwiftUI

public struct AppearanceSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @Environment(\.colorScheme) private var scheme
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
            SettingsHeader("Appearance")
            SettingsCard {
                // Every appearance is offered — System, Light, Dark — so the
                // whole light design stays reachable.
                HStack(spacing: 10) {
                    ForEach(AetherAppearance.allCases) { option in
                        appearanceCard(option)
                    }
                }
                .padding(10)
            }
        }
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Loading indicator")
            SettingsCard {
                VStack(alignment: .leading, spacing: 2) {
                    SettingsRow("Progress line color", symbol: "eyedropper") { EmptyView() }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 5), spacing: 4) {
                        ForEach(AetherProgressColor.allCases) { option in
                            AetherColorChoice(title: option.rawValue,
                                              color: option.color,
                                              selected: workspace.preferences.progressColor == option) {
                                workspace.preferences.progressColor = option
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func appearanceCard(_ option: AetherAppearance) -> some View {
        let selected = workspace.preferences.appearance == option
        // `.system` previews as whatever macOS is currently using.
        let dark = (option.colorScheme ?? scheme) == .dark
        return Button { workspace.preferences.appearance = option } label: {
            VStack(spacing: 8) {
                ZStack {
                    AetherPalette.canvas(dark)
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AetherPalette.subtle(dark))
                            .frame(height: 8)
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AetherPalette.surface(dark))
                                .frame(width: 24)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AetherPalette.surface(dark))
                        }
                    }
                    .padding(9)
                }
                .frame(height: 70)
                .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous)
                        .strokeBorder(skin.cardBorder, lineWidth: 0.5)
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(selected ? skin.primaryText : .clear)
                        .frame(width: 5, height: 5)
                        .overlay { Circle().strokeBorder(skin.secondaryText, lineWidth: selected ? 0 : 1) }
                    Text(option.rawValue)
                        .font(AetherType.body(12))
                        .foregroundStyle(skin.primaryText)
                    Spacer(minLength: 4)
                }
            }
            .padding(9)
            .background(selected ? skin.selectionFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: AetherMetrics.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .aetherPointingCursor()
        .focusEffectDisabled()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
