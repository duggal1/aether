import SwiftUI

public struct HoverSurface<Content: View>: View {
    @Environment(\.aetherTheme) private var theme
    @BrowserState private var hover = false
    let selected: Bool
    let radius: CGFloat
    let content: Content
    public init(selected: Bool = false, radius: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.selected = selected; self.radius = radius; self.content = content()
    }
    public var body: some View {
        content
            .background { surface }
            .onHover { hover = $0 }
    }

    @ViewBuilder private var surface: some View {
        if selected || hover {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(selected ? theme.selection : theme.hover)
        }
    }
}
