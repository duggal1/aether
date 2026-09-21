import SwiftUI

public struct SettingsToggle: View {
    let title: String
    let subtitle: String?
    let customIcon: AetherCustomIcon?
    @Binding var value: Bool
    public init(_ title: String, subtitle: String? = nil, customIcon: AetherCustomIcon? = nil, value: Binding<Bool>) {
        self.title = title; self.subtitle = subtitle; self.customIcon = customIcon; _value = value
    }
    public var body: some View {
        AetherRow(title, subtitle: subtitle, customIcon: customIcon) {
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

public struct SettingsDivider: View {
    @Environment(\.aetherTheme) private var theme
    public init() {}
    public var body: some View {
        Rectangle()
            .fill(theme.faintLine)
            .frame(height: 0.5)
            .padding(.leading, 12)
    }
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

public struct AetherColorChoice: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    let title: String
    let color: Color
    let selected: Bool
    let action: () -> Void

    public init(title: String, color: Color, selected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.selected = selected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle().strokeBorder(theme.hairline, lineWidth: 1)
                    }
                    .overlay {
                        if selected {
                            Circle()
                                .strokeBorder(theme.ink, lineWidth: 1.5)
                                .padding(-3)
                        }
                    }
                Text(title)
                    .font(AetherType.body(12))
                    .foregroundStyle(selected ? theme.ink : theme.muted)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aetherPointingCursor()
        .focusEffectDisabled()
        .animation(AetherMotion.selection(reduced), value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
