import SwiftUI

public struct BrowserWindowView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.openWindow) private var openWindow
    let window: BrowserWindowModel
    public init(window: BrowserWindowModel) { self.window = window }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                if window.arrangement == .sidebar && !window.sidebarCollapsed {
                    SidebarTabListView(window: window)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .overlay(alignment: .trailing) {
                            SidebarResizeHandle(preferences: window.workspace.preferences)
                        }
                }
                VStack(spacing: 0) {
                    if window.arrangement == .top {
                        TopTabStripView(window: window)
                            .zIndex(2)
                    }
                    VStack(spacing: 0) {
                        NavigationBarView(window: window, showsChrome: false).zIndex(10)
                        BrowserContentView(window: window, surfaces: window.surfaces)
                    }
                    .background(theme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.leading, window.arrangement == .top ? 6 : 0)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                    .padding(.top, window.arrangement == .sidebar ? 6 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if window.showsTabSearch {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { window.showsTabSearch = false }
                    .zIndex(20)
                AetherCommandPalette(window: window)
                    .padding(.top, window.arrangement == .top ? 42 : 48)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .transition(AetherMotion.panelTransition(reduced))
                    .zIndex(21)
            }
        }
        .frame(minWidth: 760, minHeight: 460)
        .background { AetherChromeBackground(.sidebar) }
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
