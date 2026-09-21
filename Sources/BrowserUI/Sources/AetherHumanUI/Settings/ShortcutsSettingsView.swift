import SwiftUI

public struct ShortcutsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    private let shortcuts: [(String, String)] = [
        ("New tab", "⌘T"), ("Close tab", "⌘W"), ("Restore closed tab", "⇧⌘T"),
        ("Focus address bar", "⌘L"), ("Reload page", "⌘R"),
        ("Next tab", "⌃⇥"), ("Previous tab", "⌃⇧⇥"),
        ("History", "⌘Y"), ("Bookmarks", "⌥⌘B"),
        ("Toggle tab layout", "⌥⌘S")
    ]
    public init() {}
    public var body: some View {
        SettingsHelp("Keyboard-first browsing. These are Aether shell shortcuts; webpage shortcuts are delivered by the engine.")
        AetherSection("Browser") {
            ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, item in
                if index > 0 { SettingsDivider() }
                AetherRow(item.0) {
                    Text(item.1).font(AetherType.mono(11)).foregroundStyle(theme.muted)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(theme.settingsRaised, in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}
