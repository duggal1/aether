import SwiftUI

public struct GeneralSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }
    public var body: some View {
        SettingsHelp("Choose how Aether starts and which profile new windows use.")
        AetherSection("On startup") {
            AetherRow("Restore previous windows", subtitle: "Requires engine-backed page restoration, not just saved tab labels.") {
                Toggle("Restore previous windows", isOn: Binding(get: { workspace.preferences.restoreWindows }, set: { workspace.preferences.restoreWindows = $0 })).labelsHidden()
            }
        }
        AetherSection("New windows") {
            AetherRow("Open with profile") {
                Menu {
                    ForEach(workspace.profiles) { profile in
                        Button(profile.name) { workspace.setDefaultProfile(profile.id) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(workspace.name(for: workspace.defaultProfileID))
                            .font(AetherType.body(12)).lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(AetherType.symbol(10, weight: .regular))
                            .foregroundStyle(theme.muted)
                    }
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 10)
                    .frame(width: 160, height: 28)
                    .background(theme.hover, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .aetherFocusTreatment(radius: 6)
                .help("Choose the profile for new windows")
                .accessibilityLabel("Open new windows with profile")
            }
        }
        SettingsHelp("Browser data, JavaScript execution, renderer behavior and profile security remain owned by the existing Aether engine.")
    }
}
