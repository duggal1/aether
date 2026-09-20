import SwiftUI

public struct AppearanceSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    public var body: some View {
        SettingsHelp("Websites follow Aether's appearance. Sites with a native dark theme use it; light pages receive a dark color adjustment that preserves images and video.")
        AetherSection("Appearance") {
            HStack(spacing: 12) {
                ForEach(AetherAppearance.allCases) { option in appearanceCard(option) }
            }
            .padding(12)
        }
        SettingsHelp("System mode follows macOS appearance changes. Focus rings, Reduce Motion, Reduce Transparency and Increase Contrast stay managed by the system.")
        AetherSection("Loading indicator") {
            AetherRow("Progress line color", subtitle: "Thin loading line under the address bar.") {
                Picker("Progress line color", selection: Binding(get: { workspace.preferences.progressColor }, set: { workspace.preferences.progressColor = $0 })) {
                    ForEach(AetherProgressColor.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
        }
    }

    private func appearanceCard(_ option: AetherAppearance) -> some View {
        let selected = workspace.preferences.appearance == option
        return Button { workspace.preferences.appearance = option } label: {
            VStack(spacing: 10) {
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
                .frame(height: 77)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                HStack {
                    Text(option.rawValue).font(AetherType.rowTitle(12))
                    Spacer(minLength: 6)
                    Image(systemName: selected ? AetherSymbol.selected.rawValue : AetherSymbol.unselected.rawValue)
                        .font(AetherType.symbol(12))
                        .foregroundStyle(selected ? theme.ink : theme.soft)
                }
            }
            .foregroundStyle(theme.ink)
            .padding(10)
            .background(selected ? theme.hover : theme.surface,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
    }
}
