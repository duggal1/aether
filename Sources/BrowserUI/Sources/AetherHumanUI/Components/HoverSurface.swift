import SwiftUI

public struct HoverSurface<Content: View>: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var hover = false
    let selected: Bool
    let radius: CGFloat
    let content: Content
    public init(selected: Bool = false, radius: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.selected = selected; self.radius = radius; self.content = content()
    }
    public var body: some View {
        content
            .background(selected ? theme.selection : hover ? theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { on in withAnimation(AetherMotion.hover(reduced)) { hover = on } }
    }
}
