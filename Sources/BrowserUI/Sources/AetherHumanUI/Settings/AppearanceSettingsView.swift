import SwiftUI

public struct AppearanceSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        SettingsHelp("Aether's stone-based design works in both appearances. Websites keep their own colors.")
        AetherSection("Appearance") {
            HStack(spacing: 12) {
                ForEach(AetherAppearance.allCases) { option in appearanceCard(option) }
            }.padding(12)
        }
        SettingsHelp("System mode follows macOS appearance changes. Native focus, accessibility preferences and Reduce Motion remain managed by the system.")
    }
    private func appearanceCard(_ option: AetherAppearance) -> some View {
        let selected = workspace.preferences.appearance == option
        return Button { workspace.preferences.appearance = option } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(option == .dark ? AetherPalette.canvas(true) : AetherPalette.canvas(false))
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(option == .dark ? AetherPalette.subtle(true) : AetherPalette.subtle(false))
                            .frame(height: 8)
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(option == .dark ? AetherPalette.surface(true) : AetherPalette.surface(false)).frame(width: 24)
                            RoundedRectangle(cornerRadius: 2).fill(option == .dark ? AetherPalette.surface(true) : AetherPalette.surface(false))
                        }
                    }.padding(9)
                }.frame(height: 77)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.line, lineWidth: 1))
                HStack {
                    Text(option.rawValue).font(AetherType.medium(12))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12)).foregroundStyle(selected ? theme.ink : theme.soft)
                }
            }
            .foregroundStyle(theme.ink).padding(10)
            .background(theme.raised, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? theme.muted : theme.line, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
