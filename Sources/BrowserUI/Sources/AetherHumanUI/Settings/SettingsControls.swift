import SwiftUI

public struct SettingsToggle: View {
    let title: String
    let subtitle: String?
    @Binding var value: Bool
    public init(_ title: String, subtitle: String? = nil, value: Binding<Bool>) {
        self.title = title; self.subtitle = subtitle; _value = value
    }
    public var body: some View {
        AetherRow(title, subtitle: subtitle) {
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

public struct SettingsDivider: View {
    public init() {}
    public var body: some View { Divider().padding(.leading, 12) }
}

public struct SettingsHelp: View {
    @Environment(\.aetherTheme) private var theme
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text).font(AetherType.body(12)).foregroundStyle(theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
