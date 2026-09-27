import SwiftUI

struct AetherMenuRow<Content: View>: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @State private var hovering = false
    let radius: CGFloat
    let content: Content
    init(radius: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }
    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill((surface ?? AetherSurfaceResolver.themed(dark: theme.dark)).hoverFill)
                    .opacity(hovering ? 1 : 0)
            }
            .onHover { hovering = $0 }
    }
}

struct AetherMenuPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .focusEffectDisabled()
            .modifier(AetherPointingCursor())
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
    }
}

public struct MoreMenuView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
    @Environment(\.accessibilityReduceMotion) private var reduced
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var skin: AetherSurfaceStyle {
        surface ?? AetherSurfaceResolver.themed(dark: theme.dark)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row("Search Tabs", .search) { window.showsTabSearch = true }
            row("History", .history) { window.showHistoryPanel() }
            row("Bookmarks", .bookmark) { window.showBookmarksPanel() }
            row("Downloads", .downloadFolder) { window.showsDownloads = true }
            Divider().overlay(skin.separator).padding(.vertical, 5)
            row("Find in Page", .search) { window.showsFind = true }
            row("Reader", .reader) { window.showsReader = true }
            row("Site Information", .globe) { window.showsSiteCard = true }
            row("Hidden Elements…", .inspect) { window.showsVeils = true }
            // Frontend-only trim (correction pass §1): Inspect Page, Float Video
            // and Mute Tab remain fully implemented in BrowserCommands /
            // BrowserWindowModel — they are only not rendered in this menu.
            Divider().overlay(skin.separator).padding(.vertical, 5)
            row(window.arrangement == .top ? "Use Sidebar Tabs" : "Use Top Tabs", .sidebar) {
                window.toggleArrangement()
            }
            Button(action: { window.showsMoreMenu = false; window.showsSettings = true }) {
                menuLabel(.gear, "Settings")
            }
            .buttonStyle(AetherMenuPressStyle())
            .focusEffectDisabled()
        }
        .padding(6)
        .frame(width: 232)
        .background { AetherPopoverBackground() }
        .preferredColorScheme(skin.isDark ? .dark : .light)
        .environment(\.aetherChromeAppearance, skin.isDark ? .dark : .light)
    }

    private func row(_ title: String, _ icon: BrowserIcon, action: @escaping () -> Void) -> some View {
        Button { window.showsMoreMenu = false; action() } label: {
            menuLabel(icon, title)
        }
        .buttonStyle(AetherMenuPressStyle())
        .focusEffectDisabled()
    }

    private func menuLabel(_ icon: BrowserIcon, _ title: String) -> some View {
        AetherMenuRow {
            HStack(spacing: 10) {
                BrowserIconView(icon: icon, tint: skin.primaryIcon).iconSize(14)
                Text(title).font(AetherType.body(13)).foregroundStyle(skin.primaryText)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
    }
}
