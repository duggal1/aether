import SwiftUI
import WebKit

public struct BrowserWindowView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.aetherTrafficLeading) private var trafficLeading
    @Environment(\.openWindow) private var openWindow
    @AppStorage("aether.welcomed.v1") private var hasWelcomed = false
    let window: BrowserWindowModel
    let isFullscreen: Bool
    public init(window: BrowserWindowModel, isFullscreen: Bool = false) {
        self.window = window
        self.isFullscreen = isFullscreen
    }

    private var appearanceRequestKey: String {
        let tab = window.selected
        return "\(tab?.id.uuidString ?? "")|\(tab?.url ?? "")|\(tab?.loadState == .ready)"
    }

    /// The page state, resolved once for the whole window.
    private var pageSnapshot: AetherPageSnapshot {
        AetherPageSnapshot(isBrowserPage: window.selected.map(isBrowserPage) ?? true,
                           surface: window.selected?.siteSurface,
                           declaresDark: window.selected?.sitePrefersDark)
    }

    private func isBrowserPage(_ tab: BrowserTab) -> Bool {
        WebsiteAppearanceController.isBrowserPage(tab)
    }

    /// What every floating surface in this window is drawn over: the browser's
    /// own page, a light website, or a dark website.
    private var surfaceAppearance: AetherSurfaceAppearance {
        if let override = window.workspace.preferences.appearance.chromeOverride {
            guard !(window.selected.map(isBrowserPage) ?? true) else { return .homepage }
            return override.isDark ? .darkWebsite : .lightWebsite
        }
        return AetherSurfaceResolver.appearance(for: pageSnapshot,
                                                systemDark: theme.dark,
                                                current: window.selected?.surfaceAppearance)
    }

    /// The window's own scheme, used for system-drawn affordances and for the
    /// page's `prefers-color-scheme`.
    ///
    /// A website supplies its own tone; the start page has none, so there it
    /// follows the system. Never hard-coded in either case: pinning it dark
    /// forced every website into dark rendering too.
    private var windowIsDark: Bool {
        if let chosen = window.workspace.preferences.appearance.colorScheme { return chosen == .dark }
        switch surfaceAppearance {
        case .homepage: return theme.dark
        case .lightWebsite: return false
        case .darkWebsite: return true
        }
    }

    private var windowScheme: ColorScheme { windowIsDark ? .dark : .light }

    /// The chrome role, derived from the same single answer as the cards.
    private var chromeAppearance: AetherChromeAppearance { windowIsDark ? .dark : .light }

    /// The palette every floating surface in this window consumes.
    private var surfaceStyle: AetherSurfaceStyle {
        AetherSurfaceResolver.style(surfaceAppearance, darkHomepage: windowIsDark)
    }

    /// Reads the page's tone, more than once, through the ONE shared detector
    /// (§§6–7, §17). Navigation / tab-switch / restore path; scroll / DOM /
    /// theme changes arrive via PageInteractionRelay ticks into the same
    /// controller, so the sampling script and hysteresis can never drift apart.
    ///
    /// A page can paint its background after the first read, and a single early
    /// miss used to be final for the whole session — which is how a light
    /// website kept a dark card no matter what the user did.
    @MainActor private func syncAppearance() async {
        guard let tab = window.selected else { return }
        for delay in [0.45, 1.3, 2.4] as [Double] {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            guard let live = window.selected, live.id == tab.id else { return }
            guard let pageID = live.enginePageID,
                  let webView = window.workspace.engine.surface(pageID: pageID) as? WKWebView
            else { continue }
            // Settled (page said something) → stop; silent → another pass
            // after the page has had longer to paint.
            if await WebsiteAppearanceController.shared.update(tab: live, webView: webView, systemDark: theme.dark) { return }
        }
    }

    private var showsSidebar: Bool {
        window.arrangement == .sidebar && !window.sidebarCollapsed
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                if window.arrangement == .sidebar {
                    SidebarTabListView(window: window)
                        .frame(width: showsSidebar ? nil : 0)
                        .clipped()
                        .overlay(alignment: .trailing) {
                            if showsSidebar {
                                SidebarResizeHandle(preferences: window.workspace.preferences)
                            }
                        }
                        .opacity(showsSidebar ? 1 : 0)
                        // One appearance for the chrome and the sidebar that
                        // belongs to it: warm off-white beside a light page,
                        // charcoal beside a dark one. Force-dark here is what made
                        // the sidebar look like a slab pasted onto white pages.
                        .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                        .environment(\.aetherChromeAppearance, chromeAppearance)
                        .environment(\.aetherTheme, AetherTheme(chromeAppearance.isDark ? .dark : .light))
                }
                VStack(spacing: 0) {
                    if window.arrangement == .top {
                        AetherThemeScope {
                            TopTabStripView(window: window)
                        }
                        .zIndex(2)
                        .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                        .environment(\.aetherChromeAppearance, chromeAppearance)
                    }
                    VStack(spacing: 0) {
                        AetherThemeScope {
                            NavigationBarView(window: window, showsChrome: false)
                        }
                        .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                        .environment(\.aetherChromeAppearance, chromeAppearance)
                        .zIndex(10)
                        if window.workspace.preferences.showBookmarksBar || window.showsBookmarksBarOverride == true {
                            if window.showsBookmarksBarOverride != false {
                                AetherThemeScope { BookmarksBarView(window: window) }
                                    .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                                    .environment(\.aetherChromeAppearance, chromeAppearance)
                            }
                        }
                        BrowserContentView(window: window, surfaces: window.surfaces)
                            .overlay {
                                // Click-to-dismiss lives on page content only. It
                                // must never cover the toolbar or its buttons
                                // would stop receiving clicks while a panel is open.
                                if window.showsTabSearch || window.showsHistory || window.showsBookmarks
                                    || window.showsProfileMenu || window.showsMoreMenu {
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture { closeOverlays() }
                                }
                            }
                    }
                    .clipShape(Rectangle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if window.showsTabSearch {
                AetherThemeScope {
                    AetherCommandPalette(window: window)
                }
                .padding(.top, window.arrangement == .top ? 42 : 48)
                .padding(.trailing, 8)
                .padding(.bottom, 8)
                .transition(AetherMotion.surfaceTransition(reduced, anchor: .topTrailing))
                .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                .environment(\.aetherChromeAppearance, chromeAppearance)
                .zIndex(21)
            }
            if window.showsHistory || window.showsBookmarks {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AetherThemeScope {
                        Group {
                            if window.showsHistory {
                                HistoryView(window: window)
                            } else {
                                BookmarksView(window: window)
                            }
                        }
                        .transition(AetherMotion.surfaceTransition(reduced, anchor: .center))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                .environment(\.aetherChromeAppearance, chromeAppearance)
                .zIndex(22)
            }
            if window.showsTabSwitcher {
                VStack(spacing: 0) {
                    AetherThemeScope { TabSwitcherView(window: window) }
                        .padding(.top, window.arrangement == .top ? 42 : 48)
                        .transition(AetherMotion.surfaceTransition(reduced, anchor: .top))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                .environment(\.aetherChromeAppearance, chromeAppearance)
                .zIndex(23)
            }
            if window.peekURL != nil {
                AetherThemeScope { PeekOverlayView(window: window) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                    .environment(\.aetherChromeAppearance, chromeAppearance)
                    .zIndex(24)
            }
            if window.showsWelcome || !hasWelcomed {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AetherThemeScope {
                        WelcomeView(window: window) { hasWelcomed = true }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.18))
                .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                .environment(\.aetherChromeAppearance, chromeAppearance)
                .zIndex(30)
            }
            if window.showsVeils {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AetherThemeScope { VeilPanel(window: window) }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.18))
                .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                .environment(\.aetherChromeAppearance, chromeAppearance)
                .zIndex(25)
            }
            if window.showsSiteCard {
                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        AetherThemeScope { SiteCardView(window: window) }
                            .padding(.top, window.arrangement == .top ? 80 : 48)
                            .padding(.trailing, 12)
                            .transition(AetherMotion.surfaceTransition(reduced, anchor: .topTrailing))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                .environment(\.aetherChromeAppearance, chromeAppearance)
                .zIndex(21)
            }
            if window.showsProfileMenu {
                AetherThemeScope {
                    ProfileMenuPanel(window: window)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 44)
                .padding(.leading, profileMenuLeading)
                .transition(AetherMotion.surfaceTransition(reduced, anchor: .topLeading))
                .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                .environment(\.aetherChromeAppearance, chromeAppearance)
                .zIndex(21)
            }
            if window.showsJevSignals {
                AetherThemeScope {
                    JevSignalsPanel(window: window)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 40)
                .padding(.trailing, 8)
                .transition(AetherMotion.surfaceTransition(reduced, anchor: .topTrailing))
                .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                .environment(\.aetherChromeAppearance, chromeAppearance)
                .zIndex(21)
            }
            if window.showsExtensionsMenu {
                AetherThemeScope {
                    AetherExtensionsPanel(window: window)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 44)
                .padding(.leading, profileMenuLeading)
                .transition(AetherMotion.surfaceTransition(reduced, anchor: .topLeading))
                .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                .environment(\.aetherChromeAppearance, chromeAppearance)
                .zIndex(21)
            }
            if window.showsMoreMenu {
                AetherThemeScope {
                    MoreMenuView(window: window)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, (window.arrangement == .top ? 42 : 0) + 40 + 6)
                .padding(.trailing, 8)
                .transition(AetherMotion.surfaceTransition(reduced, anchor: .topTrailing))
                .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                .environment(\.aetherChromeAppearance, chromeAppearance)
                .zIndex(21)
            }
        }
        .environment(\.aetherChromeAppearance, chromeAppearance)
        .environment(\.aetherIsFullscreen, isFullscreen)
        .environment(\.aetherSurfaceStyle, surfaceStyle)
        .frame(minWidth: 760, minHeight: 460)
        .task(id: appearanceRequestKey) { await syncAppearance() }
        .preferredColorScheme(windowScheme)
        .animation(AetherMotion.surfaceOpen(reduced), value: window.showsTabSearch)
        .animation(AetherMotion.surfaceOpen(reduced), value: window.showsHistory || window.showsBookmarks)
        .animation(AetherMotion.surfaceOpen(reduced), value: window.showsProfileMenu || window.showsMoreMenu)
        .animation(AetherMotion.surfaceOpen(reduced), value: window.showsExtensionsMenu)
        .animation(AetherMotion.surfaceOpen(reduced), value: window.showsJevSignals)
        .animation(AetherMotion.sidebar(reduced), value: window.sidebarCollapsed)
        .animation(AetherMotion.sidebar(reduced), value: window.arrangement)
        // Dialogs are window surfaces, not page surfaces: AetherDialogScope pins
        // each one's card, text and fields to the window's own scheme. The same
        // resolved surface rides along, so one dialog is solid over the start
        // page and a blur card over a website — never three material systems.
        .sheet(isPresented: Binding(get: { window.showsNewProfile }, set: { window.showsNewProfile = $0 })) {
            AetherDialogScope { NewProfileSheet(window: window) }
                .environment(\.aetherSurfaceStyle, surfaceStyle)
        }
        .sheet(isPresented: Binding(get: { window.showsRenameProfile }, set: { window.showsRenameProfile = $0 })) {
            AetherDialogScope { RenameProfileSheet(window: window) }
                .environment(\.aetherSurfaceStyle, surfaceStyle)
        }
        .sheet(isPresented: Binding(get: { window.showsDownloads }, set: { window.showsDownloads = $0 })) {
            AetherDialogScope { DownloadsView(window: window) }
                .environment(\.aetherSurfaceStyle, surfaceStyle)
        }
        .sheet(isPresented: Binding(get: { window.showsInspector }, set: { window.showsInspector = $0 })) {
            AetherDialogScope { InspectorView(window: window) }
                .environment(\.aetherSurfaceStyle, surfaceStyle)
        }
        .sheet(isPresented: Binding(get: { window.showsReader }, set: { window.showsReader = $0 })) {
            AetherDialogScope { ReaderView(window: window) }
                .environment(\.aetherSurfaceStyle, surfaceStyle)
        }
        .sheet(isPresented: Binding(get: { window.showsSettings }, set: { window.showsSettings = $0 })) {
            AetherDialogScope { SettingsWindowView(workspace: window.workspace) }
        }
        .alert("Aether", isPresented: Binding(get: { window.alert != nil }, set: { if !$0 { window.alert = nil } })) {
            Button("OK") { window.alert = nil }
        } message: { Text(window.alert ?? "") }
        .confirmationDialog("Save password for \(credentialOfferHost)?",
                           isPresented: Binding(get: { window.credentialSaveOffer != nil },
                                                set: { if !$0 { window.dismissCredentialSave() } }),
                           titleVisibility: .visible) {
            Button("Save Password") { window.acceptCredentialSave() }
            Button("Not Now", role: .cancel) { window.dismissCredentialSave() }
        } message: {
            Text("The password will be stored in this Mac's Keychain and offered only on this exact website origin.")
        }
    }

    private func closeOverlays() {
        window.showsTabSearch = false
        window.showsHistory = false
        window.showsBookmarks = false
        window.showsTabSwitcher = false
        window.showsSiteCard = false
        window.closeMenus()
    }

    private var profileMenuLeading: CGFloat {
        if isFullscreen { return 12 }
        return trafficLeading + (window.arrangement == .top ? 2 : 0)
    }

    private var credentialOfferHost: String {
        window.credentialSaveOffer.flatMap { URL(string: $0.origin)?.host } ?? "this website"
    }
}
