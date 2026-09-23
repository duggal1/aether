import AppKit
import SwiftUI

struct SecondaryClickSurface: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> SecondaryClickView {
        let view = SecondaryClickView()
        view.action = action
        return view
    }

    func updateNSView(_ view: SecondaryClickView, context: Context) {
        view.action = action
    }
}

final class SecondaryClickView: NSView {
    var action: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent,
              event.type == .rightMouseDown ||
                (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) else { return nil }
        return super.hitTest(point)
    }

    override func rightMouseDown(with event: NSEvent) { action?() }
    override func mouseDown(with event: NSEvent) { action?() }
}
