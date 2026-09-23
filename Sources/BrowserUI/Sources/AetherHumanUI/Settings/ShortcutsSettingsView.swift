import SwiftUI

public struct ShortcutsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    private let shortcuts: [(String, [AetherCustomIcon], String)] = [
        ("New tab", [.kbdCommand], "T"),
        ("Close tab", [.kbdCommand], "W"),
        ("Restore closed tab", [.kbdShift, .kbdCommand], "T"),
        ("Focus address bar", [.kbdCommand], "L"),
        ("Reload page", [.kbdCommand], "R"),
        ("Next tab", [.kbdControl, .kbdTab], ""),
        ("Previous tab", [.kbdControl, .kbdShift, .kbdTab], ""),
        ("History", [.kbdCommand], "Y"),
        ("Bookmarks", [.kbdOption, .kbdCommand], "B"),
        ("Toggle tab layout", [.kbdOption, .kbdCommand], "S"),
    ]
    public init() {}
    public var body: some View {
        AetherSection("Browser") {
            ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, item in
                if index > 0 { SettingsDivider() }
                AetherRow(item.0) {
                    HStack(spacing: 3) {
                        ForEach(item.1, id: \.self) { modifier in
                            AetherCustomIconView(modifier, tint: theme.muted, size: 11)
                        }
                        Text(item.2).font(AetherType.data(11)).foregroundStyle(theme.muted)
                    }
                    .frame(minWidth: 52, minHeight: 24)
                    .padding(.horizontal, 8)
                    .background(theme.hover, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }
}
