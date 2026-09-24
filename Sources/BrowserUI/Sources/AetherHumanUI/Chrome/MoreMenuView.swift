import SwiftUI

struct AetherMenuRow<Content: View>: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var hovering = false
    let radius: CGFloat
    let content: Content
    init(radius: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }
    var body: some View {
        content
            .background { surface }
            .onHover { hovering = $0 }
    }

    @ViewBuilder private var surface: some View {
        AetherInteractionSurface(active: hovering, radius: radius)
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
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    private var appearance: AetherChromeAppearance { chrome ?? (theme.dark ? .dark : .light) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row("Search Tabs", .search) { window.showsTabSearch = true }
            row("History", .history) { window.showsHistory = true }
            row("Bookmarks", .bookmark) { window.showsBookmarks = true }
            row("Downloads", .downloadFolder) { window.showsDownloads = true }
            Divider().padding(.vertical, 5)
            row("Find in Page", .search) { window.showsFind = true }
            row("Reader", .reader) { window.showsReader = true }
            row("Inspect Page", .inspect) { window.showsInspector = true }
            Divider().padding(.vertical, 5)
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
        .preferredColorScheme(appearance.isDark ? .dark : .light)
        .environment(\.aetherChromeAppearance, appearance)
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
                BrowserIconView(icon: icon, tint: appearance.icon).iconSize(14)
                Text(title).font(AetherType.body(13)).foregroundStyle(appearance.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
    }
}
