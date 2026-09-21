import AppKit
import SwiftUI

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
    public init(pageID: String, engine: any BrowserEnginePort, registry: PageSurfaceRegistry) {
        self.pageID = pageID; self.engine = engine; self.registry = registry
    }
    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }
    public func updateNSView(_ container: NSView, context: Context) {
        guard let realSurface = registry.surface(for: pageID, engine: engine) else { return }
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
    static func tune(_ root: NSView) {
        tuneRecursively(root)
    }

    private static func tuneRecursively(_ view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.scrollerStyle = .overlay
            scrollView.scrollerKnobStyle = .dark
        }
        for subview in view.subviews { tuneRecursively(subview) }
    }
}
