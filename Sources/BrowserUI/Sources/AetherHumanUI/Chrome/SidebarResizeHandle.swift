import SwiftUI

public struct SidebarResizeHandle: View {
    @Environment(\.aetherTheme) private var theme
    @BrowserState private var initialWidth: Double?
    let preferences: BrowserPreferences
    public init(preferences: BrowserPreferences) { self.preferences = preferences }
    public var body: some View {
        Rectangle().fill(theme.faintLine)
            .frame(width: 1)
            .frame(width: 6)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if initialWidth == nil { initialWidth = preferences.sidebarWidth }
                    let next = (initialWidth ?? preferences.sidebarWidth) + Double(value.translation.width)
                    preferences.sidebarWidth = min(AetherMetrics.maxSidebarWidth, max(AetherMetrics.minSidebarWidth, next))
                }
                .onEnded { _ in initialWidth = nil }
            )
            .help("Drag to resize sidebar")
    }
}
