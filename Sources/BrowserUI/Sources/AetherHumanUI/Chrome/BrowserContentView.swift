import SwiftUI
import WebKit

public struct BrowserContentView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    let window: BrowserWindowModel
    let surfaces: PageSurfaceRegistry
    public init(window: BrowserWindowModel, surfaces: PageSurfaceRegistry) {
        self.window = window
        self.surfaces = surfaces
    }
    public var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            if let tab = window.selected {
                switch tab.loadState {
                case .newTab:
                    NewTabView(window: window)
                case .loading, .ready:
                    if let pageID = tab.enginePageID {
                        PersistentPageSurface(pageID: pageID, engine: window.workspace.engine, registry: surfaces, window: window)
                            .id("\(tab.id.uuidString)|\(window.floatingPageID ?? "embedded")")
                            .task(id: pageID) {
                                guard let activating = window.workspace.engine as? any BrowserPageActivating else { return }
                                do {
                                    try await activating.activate(pageID: pageID)
                                    try await window.refresh(tab)
                                } catch {
                                    guard !Task.isCancelled, !BrowserWindowModel.isCancellation(error),
                                          !tab.contentReady else { return }
                                    tab.loadState = .failed(error.localizedDescription)
                                }
                            }
                    } else {
                        AetherEmptyState(icon: .globe, heading: "Preparing page", description: "Waiting for the existing browser engine.")
                    }
                case .search(let query):
                    JevSearchResultsView(query: query, window: window)
                case .failed(let message):
                    errorPage(message, tab: tab)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .topLeading) {
            if let interaction = window.agentInteraction,
               window.selected?.enginePageID == interaction.pageID.description,
               interaction.kind != .idle {
                AgentCursorOverlay(update: interaction)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.12), value: window.agentInteraction == nil)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if window.workspace.preferences.showStatusLine, let address = window.hoveredLink {
                HStack {
                    if window.linkPreviewOnRight { Spacer(minLength: 0) }
                    Text(address)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(theme.background, in: Capsule())
                    if !window.linkPreviewOnRight { Spacer(minLength: 0) }
                }
                .padding(10)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if window.showsFind {
                AetherThemeScope {
                    FindBarView(window: window)
                }
                .environment(\.colorScheme, (chrome?.isDark ?? theme.dark) ? .dark : .light)
                .environment(\.aetherChromeAppearance, chrome ?? (theme.dark ? .dark : .light))
                .padding(13)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(AetherMotion.popover(reduced), value: window.showsFind)
        .onChange(of: window.selected?.enginePageID) { oldPageID, newPageID in
            guard oldPageID != newPageID, let oldPageID else { return }
            window.takeHumanControl(from: oldPageID)
        }
    }

    private func errorPage(_ message: String, tab: BrowserTab) -> some View {
        VStack(spacing: 16) {
            BrowserIconView(icon: .warning, tint: theme.error).iconSize(26)
            Text("This page could not be opened")
                .font(AetherType.panelTitle(17)).tracking(AetherTracking.heading).foregroundStyle(theme.heading)
            Text(message).font(AetherType.body(12)).foregroundStyle(theme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack(spacing: 8) {
                if let url = tab.pendingURL ?? tab.url { Button("Try again") { window.navigate(tab, text: url) } }
                Button("New Tab") { _ = window.newTab() }
            }
            .aetherButton()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }
}
