import SwiftUI

public struct ShortcutsSettingsView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    // Apple-native key caps: real modifier glyphs as text, exactly like macOS
    // menus render them. No drawn icons anywhere in Settings.
    private let shortcuts: [(String, [String], String)] = [
        ("New tab", ["⌘"], "T"),
        ("Close tab", ["⌘"], "W"),
        ("Restore closed tab", ["⇧", "⌘"], "T"),
        ("Focus address bar", ["⌘"], "L"),
        ("Reload page", ["⌘"], "R"),
        ("Toggle sidebar", ["⌘"], "B"),
        ("Next tab", ["⌃", "⇥"], ""),
        ("Previous tab", ["⌃", "⇧", "⇥"], ""),
        ("History", ["⌘"], "Y"),
        ("Bookmarks", ["⌥", "⌘"], "B"),
        ("Toggle tab layout", ["⌥", "⌘"], "S"),
    ]
    public init() {}

    private var skin: AetherSurfaceStyle {
        if let surface, !surface.isHomepage { return surface }
        return AetherSurfaceResolver.style(theme.dark ? .darkWebsite : .lightWebsite,
                                            darkHomepage: theme.dark)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsHeader("Browser")
            SettingsCard {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, item in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(item.0) {
                        HStack(spacing: 2) {
                            ForEach(item.1, id: \.self) { modifier in
                                Text(modifier)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(skin.secondaryText)
                            }
                            if !item.2.isEmpty {
                                Text(item.2)
                                    .font(AetherType.data(11))
                                    .foregroundStyle(skin.secondaryText)
                            }
                        }
                        .frame(minWidth: 52, minHeight: 24)
                        .padding(.horizontal, 8)
                        .background(skin.controlFill, in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
    }
}
