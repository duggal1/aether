import SwiftUI

public struct SidebarResizeHandle: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @BrowserState private var initialWidth: Double?
    @BrowserState private var hovering = false
    let preferences: BrowserPreferences
    public init(preferences: BrowserPreferences) { self.preferences = preferences }

    public var body: some View {
        Rectangle()
            .fill(hovering || initialWidth != nil ? theme.hairline : .clear)
            .frame(width: 1)
            .frame(width: 7, alignment: .center)
            .offset(x: 3.5)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .onHover { value in withAnimation(AetherMotion.hover(reduced)) { hovering = value } }
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if initialWidth == nil { initialWidth = preferences.transientSidebarWidth ?? preferences.sidebarWidth }
                    let next = (initialWidth ?? preferences.sidebarWidth) + Double(value.translation.width)
                    preferences.transientSidebarWidth = min(AetherMetrics.maxSidebarWidth, max(AetherMetrics.minSidebarWidth, next))
                }
                .onEnded { _ in
                    if let pending = preferences.transientSidebarWidth {
                        preferences.sidebarWidth = pending
                    }
                    preferences.transientSidebarWidth = nil
                    initialWidth = nil
                }
            )
            .help("Drag to resize sidebar")
    }
}
