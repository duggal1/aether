import SwiftUI

public struct SettingsSidebarView: View {
    @Environment(\.aetherTheme) private var theme
    @Binding var selection: SettingsSection
    public init(selection: Binding<SettingsSection>) { _selection = selection }
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "asterisk").font(.system(size: 17, weight: .light))
                Text("Aether").font(AetherType.medium(15))
            }
            .foregroundStyle(theme.heading)
            .padding(.horizontal, 12).padding(.top, 24).padding(.bottom, 24)
            ForEach(SettingsSection.allCases) { section in
                Button { selection = section } label: {
                    HStack(spacing: 11) {
                        Image(systemName: section.icon).font(.system(size: 12)).frame(width: 17)
                        Text(section.rawValue).font(AetherType.body(12)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(selection == section ? theme.ink : theme.muted)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(selection == section ? theme.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Spacer()
            Text("NATIVE · MACOS")
                .font(AetherType.medium(9)).foregroundStyle(theme.soft).padding(.horizontal, 12).padding(.bottom, 20)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AetherChromeBackground(.settingsSidebar) }
    }
}
