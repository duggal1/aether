import AppKit
import CoreSpotlight
import SwiftUI

public struct BrowserWindowRoot: View {
    @BrowserState private var window: BrowserWindowModel?
    @State private var nativeWindow: NSWindow?
    @State private var isFullscreen = false
    @State private var trafficLeading: CGFloat = 72
    @State private var trackingRefresh: Task<Void, Never>?
    private let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) {
        self.workspace = workspace
    }
    public var body: some View {
        // The app appearance is a real preference (System / Light / Dark), not a
        // hard-coded dark shell.
        AetherThemeScope(workspace.preferences.appearance) {
            if let window {
            BrowserWindowView(window: window, isFullscreen: isFullscreen)
                .aetherTypography()
                .background {
                    AetherWindowProbeView { value in
                        nativeWindow = value
                        window.nativeWindow = value
                        isFullscreen = value.styleMask.contains(.fullScreen)
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.3))
                            measureTrafficLights()
                        }
                    }.allowsHitTesting(false)
                }
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .focusedSceneValue(\.aetherWindow, window)
                .task { await window.restoreProfile() }
            }
        }
        .task {
            if window == nil { window = BrowserWindowModel(workspace: workspace) }
            await workspace.syncSearchKeysToEngine()
        }
        .environment(\.aetherTrafficLeading, trafficLeading)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            if let value = notification.object as? NSWindow, value === nativeWindow { isFullscreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            if let value = notification.object as? NSWindow, value === nativeWindow { isFullscreen = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let value = notification.object as? NSWindow, value === nativeWindow { window?.becameKeyWindow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            window?.applicationWillResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            window?.applicationDidBecomeActive()
        }
        .onChange(of: isFullscreen) { _, _ in
            // AppKit rebuilds the titlebar as part of the style-mask change, and
            // a rebuilt titlebar is interactive again by default. Re-state the
            // window's configuration so the strip above the chrome can never
            // become a drag region that eats the toolbar's clicks.
            if let nativeWindow { AetherWindowProbe.configure(nativeWindow) }
            measureTrafficLights()
            refreshHoverTracking()
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let id = UUID(uuidString: raw),
                  let bookmark = workspace.bookmarks.first(where: { $0.id == id }),
                  let window else { return }
            window.switchProfile(bookmark.profileID)
            _ = window.newTab(url: bookmark.url)
        }
    }

    private func measureTrafficLights() {
        guard let nativeWindow, !isFullscreen else { return }
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let maxX = types.compactMap { nativeWindow.standardWindowButton($0)?.frame.maxX }.max()
        if let maxX { trafficLeading = maxX + 8 }
    }

    private func refreshHoverTracking() {
        trackingRefresh?.cancel()
        trackingRefresh = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))
            guard !Task.isCancelled else { return }
            if let contentView = nativeWindow?.contentView {
                nativeWindow?.invalidateCursorRects(for: contentView)
            }
        }
    }
}


// The window stays non-opaque so the sidebar's behind-window material can frost
// the desktop — the native sidebar look. Every other pixel is painted by the
// opaque SwiftUI root, so nothing else can show the desktop through.
private struct AetherWindowProbeView: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> AetherWindowProbe {
        let view = AetherWindowProbe()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ view: AetherWindowProbe, context: Context) {}
}

/// Decorative probe. It reports the window and nothing else, so it must never
/// participate in hit-testing: a live probe view sitting above the chrome is one
/// of the ways toolbar controls go dead.
///
/// It also owns the window's chrome configuration, and re-applies it whenever
/// the style mask changes. Entering or leaving fullscreen makes AppKit rebuild
/// the titlebar, and a rebuilt titlebar is interactive again by default: a
/// transparent-looking strip that silently swallows the clicks aimed at the
/// controls underneath it. Everything the app needs — a clear, non-opaque
/// window so the sidebar can frost the desktop, a hidden title, and a titlebar
/// that is never a drag region over the chrome — is therefore stated in one
/// place and re-stated after every fullscreen transition.
private final class AetherWindowProbe: NSView {
    var onWindow: ((NSWindow) -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Self.configure(window)
        Task { @MainActor [weak self] in self?.onWindow?(window) }
    }

    /// One definition of "how this window's chrome behaves", applied on
    /// creation and again after every style-mask change.
    static func configure(_ window: NSWindow) {
        // Non-opaque and clear so the sidebar's behind-window material has
        // something to frost; every other pixel is painted by the SwiftUI root.
        window.isOpaque = false
        window.backgroundColor = .clear
        // The content view owns the whole window, including the strip where the
        // titlebar used to be. A title, a titlebar fill or a separator here is
        // decoration drawn on top of the app's own chrome.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // Dragging the window by its background would take the click before the
        // control under the pointer ever saw it.
        window.isMovableByWindowBackground = false
    }
}
