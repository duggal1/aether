import AppKit
import CoreSpotlight
import SwiftUI

public struct BrowserWindowRoot: View {
    @BrowserState private var window: BrowserWindowModel?
    @State private var nativeWindow: NSWindow?
    @State private var isFullscreen = false
    @State private var trafficLeading: CGFloat = 72
    @State private var chromeTick = 0
    @State private var trackingRefresh: Task<Void, Never>?
    private let workspace: BrowserWorkspace
    public init(workspace: BrowserWorkspace) {
        self.workspace = workspace
    }
    public var body: some View {
        AetherThemeScope {
            if let window {
            BrowserWindowView(window: window, isFullscreen: isFullscreen, refreshTick: chromeTick)
                .aetherTypography()
                .background {
                    AetherWindowTransparencyView { value in
                        nativeWindow = value
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
        .onChange(of: isFullscreen) { _, _ in
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

    // The animated Space jump can leave AppKit hover/cursor tracking stale
    // while rendering stays correct. Re-register cursor rects and rebuild the
    // chrome (never the page) once frames settle after the transition.
    private func refreshHoverTracking() {
        trackingRefresh?.cancel()
        trackingRefresh = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))
            guard !Task.isCancelled else { return }
            if let contentView = nativeWindow?.contentView {
                nativeWindow?.invalidateCursorRects(for: contentView)
            }
            chromeTick += 1
        }
    }
}


// Behind-window NSVisualEffectView can only sample desktop colors when the
// hosting window is non-opaque. The content pane paints its own opaque surface.
private struct AetherWindowTransparencyView: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = AetherWindowTransparencyProbe()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

private final class AetherWindowTransparencyProbe: NSView {
    var onWindow: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.titlebarAppearsTransparent = true
        if let window {
            Task { @MainActor [weak self] in self?.onWindow?(window) }
        }
    }
}
