import SwiftUI

public struct BrowserWindowView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.openWindow) private var openWindow
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        VStack(spacing: 0) {
            if window.arrangement == .top { TopTabStripView(window: window) }
            HStack(spacing: 0) {
                if window.arrangement == .sidebar && !window.sidebarCollapsed {
                    SidebarTabListView(window: window)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    SidebarResizeHandle(preferences: window.workspace.preferences)
                }
                VStack(spacing: 0) {
                    NavigationBarView(window: window)
                    BrowserContentView(window: window, surfaces: window.surfaces)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .background(theme.canvas)
        .preferredColorScheme(window.workspace.preferences.appearance.colorScheme)
        .sheet(isPresented: Binding(get: { window.showsHistory }, set: { window.showsHistory = $0 })) {
            HistoryView(window: window)
        }
        .sheet(isPresented: Binding(get: { window.showsBookmarks }, set: { window.showsBookmarks = $0 })) {
            BookmarksView(window: window)
        }
        .sheet(isPresented: Binding(get: { window.showsDownloads }, set: { window.showsDownloads = $0 })) {
            DownloadsView(window: window)
        }
        .sheet(isPresented: Binding(get: { window.showsInspector }, set: { window.showsInspector = $0 })) {
            InspectorView(window: window)
        }
        .sheet(isPresented: Binding(get: { window.showsReader }, set: { window.showsReader = $0 })) {
            ReaderView(window: window)
        }
        .alert("Aether", isPresented: Binding(get: { window.alert != nil }, set: { if !$0 { window.alert = nil } })) {
            Button("OK") { window.alert = nil }
        } message: { Text(window.alert ?? "") }
    }
}
