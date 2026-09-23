import SwiftUI

public struct SearchLocationSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) { self.workspace = workspace }

    public var body: some View {
        AetherSection("Search locality") {
            AetherRow("City", customIcon: .gps) {
                settingsField(binding(\.city), width: 180)
            }
            SettingsDivider()
            AetherRow("Region / State", customIcon: .nearby) {
                settingsField(binding(\.regionCode), width: 90)
            }
            SettingsDivider()
            AetherRow("Country", customIcon: .gps) {
                HStack(spacing: 8) {
                    if workspace.preferences.searchLocality.countryCode.uppercased() == "US" {
                        USFlagView()
                    }
                    settingsField(binding(\.countryCode), width: 80)
                }
            }
            SettingsDivider()
            AetherRow("Primary postal code", customIcon: .zipCode) {
                settingsField(postalBinding, width: 110)
            }
            SettingsDivider()
            AetherRow("Nearby areas", customIcon: .nearby) {
                Text("\(workspace.preferences.searchLocality.nearbyPostalCodes.count) areas")
                    .font(AetherType.body(12))
                    .foregroundStyle(theme.muted)
            }
        }
        AetherSection("Query behavior") {
            SettingsToggle("Append locality to queries",
                           customIcon: .filter,
                           value: Binding(
                            get: { workspace.preferences.localityQueryTerms },
                            set: { workspace.preferences.localityQueryTerms = $0 }))
        }
        AetherSection("Route independence") {
            AetherRow("Network exit", customIcon: .server) {
                Text(workspace.preferences.networkRoute.enabled
                     ? workspace.preferences.networkRoute.region.rawValue
                     : "Direct connection")
                    .font(AetherType.body(12))
                    .foregroundStyle(theme.muted)
            }
        }
        HStack {
            Spacer()
            Button("Reset to San Francisco") {
                workspace.preferences.searchLocality = .sanFrancisco
            }
            .aetherButton()
        }
    }

    private func binding(_ keyPath: WritableKeyPath<SearchLocality, String>) -> Binding<String> {
        Binding(
            get: { workspace.preferences.searchLocality[keyPath: keyPath] },
            set: { workspace.preferences.searchLocality[keyPath: keyPath] = $0 })
    }

    private var postalBinding: Binding<String> {        Binding(
            get: { workspace.preferences.searchLocality.postalCode ?? "" },
            set: { workspace.preferences.searchLocality.postalCode = $0.isEmpty ? nil : $0 })
    }

    private func settingsField(_ text: Binding<String>, width: CGFloat) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .font(AetherType.body(12))
            .foregroundStyle(theme.ink)
            .frame(width: width)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(theme.input, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
