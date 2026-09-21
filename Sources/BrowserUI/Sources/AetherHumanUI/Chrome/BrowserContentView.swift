import SwiftUI

public struct BrowserContentView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    let window: BrowserWindowModel
    let surfaces: PageSurfaceRegistry
    public init(window: BrowserWindowModel, surfaces: PageSurfaceRegistry) {
        self.window = window
        self.surfaces = surfaces
    }
    public var body: some View {
        ZStack {
            theme.canvas.ignoresSafeArea()
            if let tab = window.selected {
                switch tab.loadState {
                case .newTab:
                    NewTabView(window: window)
                case .loading, .ready:
                    if let pageID = tab.enginePageID {
                        PersistentPageSurface(pageID: pageID, engine: window.workspace.engine, registry: surfaces)
                            .id(tab.id)
                            .task(id: pageID) {
                                guard let activating = window.workspace.engine as? any BrowserPageActivating else { return }
                                do {
                                    try await activating.activate(pageID: pageID)
                                    try await window.refresh(tab)
                                } catch {
                                    if !Task.isCancelled { tab.loadState = .failed(error.localizedDescription) }
                                }
                            }
                    } else {
                        AetherEmptyState(icon: .globe, heading: "Preparing page", description: "Waiting for the existing browser engine.")
                    }
                case .failed(let message):
                    errorPage(message, tab: tab)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if window.showsFind {
                FindBarView(window: window)
                    .padding(13)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(AetherMotion.popover(reduced), value: window.showsFind)
    }

    private func errorPage(_ message: String, tab: BrowserTab) -> some View {
        VStack(spacing: 16) {
            BrowserIconView(icon: .warning, tint: theme.error).iconSize(26)
            Text("This page could not be opened")
                .font(AetherType.panelTitle(17)).foregroundStyle(theme.heading)
            Text(message).font(AetherType.body(12)).foregroundStyle(theme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack(spacing: 8) {
                if let url = tab.url { Button("Try again") { window.navigate(tab, text: url) } }
                Button("New Tab") { _ = window.newTab() }
            }
            .buttonStyle(.bordered)
            .pointerStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.canvas)
    }
}
