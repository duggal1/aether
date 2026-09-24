import SwiftUI
import WebKit

public struct BrowserWindowView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.aetherTrafficLeading) private var trafficLeading
    @Environment(\.openWindow) private var openWindow
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

    private var chromeAppearance: AetherChromeAppearance {
        if let previous = window.selected?.chromeAppearance { return previous }
        return AetherChromeAppearanceResolver.resolve(
            siteSurface: window.selected?.siteSurface,
            sitePrefersDark: window.selected?.sitePrefersDark,
            systemDark: theme.dark,
            current: window.selected?.chromeAppearance)
    }

    private var showsSidebar: Bool {
        window.arrangement == .sidebar && !window.sidebarCollapsed
    }

    @MainActor private func syncAppearance() async {
        try? await Task.sleep(for: .seconds(0.8))
        guard !Task.isCancelled else { return }
        guard let tab = window.selected, tab.loadState == .ready,
              let pageID = tab.enginePageID,
              let webView = window.workspace.engine.surface(pageID: pageID) as? WKWebView else { return }
        let expectedURL = tab.url
        let source = """
        (() => {
          const declared = getComputedStyle(document.documentElement).colorScheme.trim();
          const prefersDark = declared === 'dark' ? true : declared === 'light' ? false : null;
          const parse = (value) => {
            const m = /^rgba?\\((\\d+)[, ]+(\\d+)[, ]+(\\d+)(?:[, /]+([\\d.]+))?\\)/.exec(value);
            if (!m || (m[4] && Number(m[4]) < 0.92)) return null;
            return '#' + [m[1], m[2], m[3]]
              .map(x => Number(x).toString(16).padStart(2, '0')).join('');
          };
          let hex = null;
          const points = [
            document.elementFromPoint(Math.floor(innerWidth / 2), 8),
            document.body, document.documentElement
          ];
          for (const root of points) {
            for (let el = root; el; el = el.parentElement) {
              const found = parse(getComputedStyle(el).backgroundColor);
              if (found) { hex = found; break; }
            }
            if (hex) break;
          }
          if (!hex) {
            const meta = document.querySelector('meta[name="theme-color"]');
            const content = meta && meta.content ? meta.content.trim() : '';
            if (/^#[0-9a-f]{6}$/i.test(content)) { hex = content.toLowerCase(); }
          }
          return [hex, prefersDark];
        })()
        """
        guard let payload = (try? await webView.evaluateJavaScript(source)) as? [Any],
              payload.count == 2, !Task.isCancelled, tab.url == expectedURL else { return }
        let hexString = payload[0] as? String
        let color = hexString.flatMap { $0.hasPrefix("#") ? UInt($0.dropFirst(), radix: 16) : nil }
        let prefersDark = (payload[1] as? NSNumber)?.boolValue
        tab.siteSurface = color
        tab.sitePrefersDark = prefersDark
        tab.chromeAppearance = AetherChromeAppearanceResolver.resolve(
            siteSurface: color, sitePrefersDark: prefersDark,
            systemDark: theme.dark, current: tab.chromeAppearance)
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
                        .environment(\.colorScheme, .dark)
                        .environment(\.aetherChromeAppearance, .dark)
                        .environment(\.aetherTheme, AetherTheme(.dark))
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
                    .clipShape(contentShape)
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
                .transition(AetherMotion.panelTransition(reduced))
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
                        .transition(AetherMotion.sheetTransition(reduced))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                .environment(\.aetherChromeAppearance, chromeAppearance)
                .zIndex(22)
            }
            if window.showsProfileMenu {
                AetherThemeScope {
                    ProfileMenuPanel(window: window)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 44)
                .padding(.leading, profileMenuLeading)
                .transition(AetherMotion.panelTransition(reduced))
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
                .transition(AetherMotion.panelTransition(reduced))
                .environment(\.colorScheme, chromeAppearance.isDark ? .dark : .light)
                .environment(\.aetherChromeAppearance, chromeAppearance)
                .zIndex(21)
            }
        }
        .environment(\.aetherChromeAppearance, chromeAppearance)
        .environment(\.aetherIsFullscreen, isFullscreen)
        .frame(minWidth: 760, minHeight: 460)
        .task(id: appearanceRequestKey) { await syncAppearance() }
        .preferredColorScheme(window.workspace.preferences.appearance.colorScheme)
        .animation(AetherMotion.container(reduced), value: window.showsTabSearch)
        .animation(AetherMotion.container(reduced), value: window.showsHistory || window.showsBookmarks)
        .animation(AetherMotion.container(reduced), value: window.showsProfileMenu || window.showsMoreMenu)
        .animation(AetherMotion.sidebar(reduced), value: window.sidebarCollapsed)
        .animation(AetherMotion.sidebar(reduced), value: window.arrangement)
        .sheet(isPresented: Binding(get: { window.showsNewProfile }, set: { window.showsNewProfile = $0 })) {
            NewProfileSheet(window: window)
        }
        .sheet(isPresented: Binding(get: { window.showsRenameProfile }, set: { window.showsRenameProfile = $0 })) {
            RenameProfileSheet(window: window)
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

    private func closeOverlays() {
        window.showsTabSearch = false
        window.showsHistory = false
        window.showsBookmarks = false
        window.closeMenus()
    }

    private var profileMenuLeading: CGFloat {
        if isFullscreen { return 12 }
        return trafficLeading + (window.arrangement == .top ? 2 : 0)
    }

    // No rounding along the shared sidebar/browser seam: rounding there exposes
    // the window background as a gap. Outer-window rounding stays for the rest.
    private var contentShape: UnevenRoundedRectangle {
        let leading: CGFloat = isFullscreen || showsSidebar ? 0 : 10
        let trailing: CGFloat = isFullscreen ? 0 : 10
        return UnevenRoundedRectangle(
            topLeadingRadius: leading,
            bottomLeadingRadius: leading,
            bottomTrailingRadius: trailing,
            topTrailingRadius: trailing,
            style: .continuous)
    }
}
