import SwiftUI

public struct HoverSurface<Content: View>: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var floatingSurface
    @BrowserState private var hover = false
    let selected: Bool
    let radius: CGFloat
    let content: Content
    public init(selected: Bool = false, radius: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.selected = selected; self.radius = radius; self.content = content()
    }

    /// Inside a floating card the row highlight belongs to that card's tone, so
    /// a hover on a light card is never a white wash and on a dark card is never
    /// a dark one.
    private var fill: (Color, Color) {
        if let skin = floatingSurface { return (skin.hoverFill, skin.selectionFill) }
        return (theme.hover, theme.selection)
    }

    public var body: some View {
        content
            .background { surface }
            .onHover { hover = $0 }
    }

    @ViewBuilder private var surface: some View {
        if selected || hover {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(selected ? fill.1 : fill.0)
        }
    }
}
