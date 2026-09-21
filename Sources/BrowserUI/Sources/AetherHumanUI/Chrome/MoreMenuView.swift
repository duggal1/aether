import SwiftUI

struct AetherMenuRow<Content: View>: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var hovering = false
    let radius: CGFloat
    let content: Content
    init(radius: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.radius = radius
        self.content = content()
    }
    var body: some View {
        content
            .background { surface }
            .onHover { value in withAnimation(AetherMotion.hover(reduced)) { hovering = value } }
    }

    @ViewBuilder private var surface: some View {
        if hovering {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(theme.hover)
        }
    }
}

public struct MoreMenuView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row("Search Tabs", .search) { window.showsTabSearch = true }
            row("History", .history) { window.showsHistory = true }
            row("Bookmarks", .bookmark) { window.showsBookmarks = true }
            row("Downloads", .download) { window.showsDownloads = true }
            Divider().padding(.vertical, 5)
            row("Find in Page", .search) { window.showsFind = true }
            row("Reader", .web) { window.showsReader = true }
            row("Inspect Page", .terminalArrowRight) { window.showsInspector = true }
            Divider().padding(.vertical, 5)
            row(window.arrangement == .top ? "Use Sidebar Tabs" : "Use Top Tabs", .sidebar) {
                window.toggleArrangement()
            }
            Button(action: { window.showsSettings = true }) {
                menuLabel(.gear, "Settings")
            }
            .buttonStyle(AetherPressStyle(reduced: reduced))
            .focusEffectDisabled()
        }
        .padding(7)
        .frame(width: 232)
        .background { AetherPopoverBackground() }
    }

    private func row(_ title: String, _ icon: BrowserIcon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            menuLabel(icon, title)
        }
        .buttonStyle(AetherPressStyle(reduced: reduced))
        .focusEffectDisabled()
    }

    private func menuLabel(_ icon: BrowserIcon, _ title: String) -> some View {
        AetherMenuRow {
            HStack(spacing: 10) {
                BrowserIconView(icon: icon, tint: theme.muted).iconSize(14)
                Text(title).font(AetherType.body(13)).foregroundStyle(theme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
    }
}
