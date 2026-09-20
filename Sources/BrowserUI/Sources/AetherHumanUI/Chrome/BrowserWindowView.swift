import SwiftUI

public struct BrowserWindowView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.openWindow) private var openWindow
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                if window.arrangement == .top {
                    VStack(spacing: 0) {
                        TopTabStripView(window: window, showsChrome: false)
                        NavigationBarView(window: window, showsChrome: false).zIndex(1)
                    }
                    .background { AetherChromeBackground(.toolbar) }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                HStack(spacing: 0) {
                    if window.arrangement == .sidebar && !window.sidebarCollapsed {
                        SidebarTabListView(window: window)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .overlay(alignment: .trailing) {
                                SidebarResizeHandle(preferences: window.workspace.preferences)
                            }
                    }
                    VStack(spacing: 0) {
                        if window.arrangement == .sidebar {
                            NavigationBarView(window: window).zIndex(1)
                        }
                        BrowserContentView(window: window, surfaces: window.surfaces)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if window.showsTabSearch {
                Color.black.opacity(theme.dark ? 0.32 : 0.14)
                    .contentShape(Rectangle())
                    .onTapGesture { window.showsTabSearch = false }
                    .transition(.opacity)
                    .zIndex(1)
                AetherCommandPalette(window: window)
                    .transition(AetherMotion.panelTransition(reduced))
                    .zIndex(2)
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .background(theme.canvas)
        .preferredColorScheme(window.workspace.preferences.appearance.colorScheme)
        .animation(AetherMotion.panel(reduced), value: window.showsTabSearch)
        .animation(AetherMotion.sidebar(reduced), value: window.sidebarCollapsed)
        .animation(AetherMotion.sidebar(reduced), value: window.arrangement)
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
        .sheet(isPresented: Binding(get: { window.showsSettings }, set: { window.showsSettings = $0 })) {
            SettingsWindowView(workspace: window.workspace)
        }
        .alert("Aether", isPresented: Binding(get: { window.alert != nil }, set: { if !$0 { window.alert = nil } })) {
            Button("OK") { window.alert = nil }
        } message: { Text(window.alert ?? "") }
    }
}
