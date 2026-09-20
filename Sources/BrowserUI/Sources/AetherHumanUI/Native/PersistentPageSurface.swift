import AppKit
import SwiftUI

@MainActor
public final class PageSurfaceRegistry {
    private var surfaces: [String: NSView] = [:]
    public init() {}
    public func surface(for id: String, engine: any BrowserEnginePort) -> NSView? {
        if let cached = surfaces[id] { return cached }
        guard let view = engine.surface(pageID: id) else { return nil }
        surfaces[id] = view
        return view
    }
    public func release(_ id: String) { surfaces.removeValue(forKey: id) }
}

public struct PersistentPageSurface: NSViewRepresentable {
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
        if realSurface.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            realSurface.removeFromSuperview()
            realSurface.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(realSurface)
            NSLayoutConstraint.activate([
                realSurface.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                realSurface.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                realSurface.topAnchor.constraint(equalTo: container.topAnchor),
                realSurface.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
    }
}
