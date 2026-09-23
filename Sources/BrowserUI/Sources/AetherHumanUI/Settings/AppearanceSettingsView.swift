import SwiftUI

public struct AppearanceSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    public var body: some View {
        AetherSection("Appearance") {
            HStack(spacing: 10) {
                ForEach(AetherAppearance.allCases) { option in appearanceCard(option) }
            }
            .padding(10)
        }
        AetherSection("Loading indicator") {
            VStack(alignment: .leading, spacing: 2) {
                AetherRow("Progress line color", symbol: "timer") { EmptyView() }
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

    private func appearanceCard(_ option: AetherAppearance) -> some View {
        let selected = workspace.preferences.appearance == option
        return Button { workspace.preferences.appearance = option } label: {
            VStack(spacing: 8) {
                ZStack {
                    AetherPalette.canvas(option == .dark)
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(option == .dark ? AetherPalette.subtle(true) : AetherPalette.subtle(false))
                            .frame(height: 8)
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(option == .dark ? AetherPalette.surface(true) : AetherPalette.surface(false))
                                .frame(width: 24)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(option == .dark ? AetherPalette.surface(true) : AetherPalette.surface(false))
                        }
                    }
                    .padding(9)
                }
                .frame(height: 70)
                .clipShape(RoundedRectangle(cornerRadius: AetherMetrics.fieldRadius, style: .continuous))
                HStack(spacing: 5) {
                    Circle()
                        .fill(selected ? theme.ink : .clear)
                        .frame(width: 5, height: 5)
                        .overlay { Circle().strokeBorder(theme.muted, lineWidth: selected ? 0 : 1) }
                    Text(option.rawValue).font(AetherType.body(12))
                    Spacer(minLength: 4)
                }
            }
            .foregroundStyle(theme.ink)
            .padding(9)
            .background(selected ? theme.settingsRaised : Color.clear,
                        in: RoundedRectangle(cornerRadius: AetherMetrics.cardRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .aetherPointingCursor()
        .focusEffectDisabled()
    }
}
