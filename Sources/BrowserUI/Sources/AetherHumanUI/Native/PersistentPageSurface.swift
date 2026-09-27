import AppKit
import EngineRuntime
import SwiftUI
import WebKit

@MainActor
public final class PageSurfaceRegistry {
    private var surfaces: [String: NSView] = [:]
    public init() {}
    public func surface(for id: String, engine: any BrowserEnginePort) -> NSView? {
        guard let view = engine.surface(pageID: id) else { surfaces.removeValue(forKey: id); return nil }
        if let cached = surfaces[id], cached !== view { cached.removeFromSuperview() }
        surfaces[id] = view
        return view
    }
    public func release(_ id: String) { surfaces.removeValue(forKey: id) }
}

public struct PersistentPageSurface: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    public typealias NSViewType = NSView
    public let pageID: String
    public let engine: any BrowserEnginePort
    public let registry: PageSurfaceRegistry
    public let window: BrowserWindowModel
    public init(pageID: String, engine: any BrowserEnginePort, registry: PageSurfaceRegistry,
                window: BrowserWindowModel) {
        self.pageID = pageID; self.engine = engine; self.registry = registry; self.window = window
    }
    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }
    public func updateNSView(_ container: NSView, context: Context) {
        guard let realSurface = registry.surface(for: pageID, engine: engine) else { return }
        if window.floatingPageID == pageID { return }
        if let webView = realSurface as? WKWebView, window.pageInteractionRelays[pageID] == nil {
            window.pageInteractionRelays[pageID] = PageInteractionRelay.install(on: webView, pageID: pageID, window: window)
            if let pageView = webView as? AetherPageView {
                pageView.searchName = { [weak window] in window?.workspace.preferences.provider.searchName }
                pageView.onSearch = { [weak window] selection in window?.navigateSelected(selection) }
                pageView.onUnclaimedShortcut = { [weak window] key in
                    if key == "s" { window?.toggleSidebar() }
                    else if key == "f" { window?.showsFind = true }
                }
                pageView.onCredentialEvent = { [weak window, weak pageView] event in
                    guard let pageView else { return }
                    window?.receiveCredentialEvent(event, pageID: pageID, pageView: pageView)
                }
                pageView.contextMenuBuilder = { [weak window, weak pageView] context, menu, webView in
                    guard let window, let pageView else { return }
                    // The selection has to be asked for by an item that owns the
                    // page view, because reading it is asynchronous and the
                    // click that opened the menu is what clears it.
                    let search = context.hasSelection
                        ? pageView.makeSearchItem(title: "Search with \(window.workspace.preferences.provider.searchName)")
                        : nil
                    AetherContextMenu.fill(menu, context: context, window: window,
                                           webView: webView, searchItem: search)
                }
            }
        }
        let appearance = colorScheme == .dark ? NSAppearance.Name.darkAqua : .aqua
        if realSurface.appearance?.name != appearance { realSurface.appearance = NSAppearance(named: appearance) }
        if realSurface.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            realSurface.removeFromSuperview()
            realSurface.translatesAutoresizingMaskIntoConstraints = true
            realSurface.autoresizingMask = [.width, .height]
            realSurface.frame = container.bounds
            container.addSubview(realSurface)
            AetherWebScrollTuning.tune(realSurface)
        }
    }
}

enum AetherWebScrollTuning {
    private static var tuned: Set<ObjectIdentifier> = []

    static func tune(_ root: NSView) {
        let id = ObjectIdentifier(root)
        guard !tuned.contains(id) else { return }
        tuned.insert(id)
        if tuned.count > 256 { tuned.removeFirst() }
        tuneRecursively(root, depth: 0)
    }

    private static func tuneRecursively(_ view: NSView, depth: Int) {
        if let scrollView = view as? NSScrollView {
            scrollView.scrollerStyle = .overlay
            scrollView.scrollerKnobStyle = .dark
        }
        guard depth < 6 else { return }
        for subview in view.subviews { tuneRecursively(subview, depth: depth + 1) }
    }
}

struct AetherOverlayScrollerTuning: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollerProbe { OverlayScrollerProbe() }
    func updateNSView(_ view: OverlayScrollerProbe, context: Context) {}
}

/// Reports the scroller style of the scroll view it sits in. Purely decorative —
/// as a plain `NSView` it hit-tested as a full-size blank layer and could take
/// clicks from whatever sat underneath it.
final class OverlayScrollerProbe: AetherPassthroughView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        var current = superview
        while let view = current {
            if let scrollView = view as? NSScrollView {
                scrollView.scrollerStyle = .overlay
                break
            }
            current = view.superview
        }
    }
}
