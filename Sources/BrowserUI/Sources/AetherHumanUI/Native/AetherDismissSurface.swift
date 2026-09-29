import AppKit
import SwiftUI

/// Closes the window's floating surfaces on a press over the page.
///
/// It claims the press and nothing else. A hit test that answers only for mouse
/// downs leaves every other event — the scroll wheel above all — to the view
/// underneath, so the page goes on scrolling while a menu, the history panel or
/// the extensions drawer is open. A SwiftUI tap gesture over the same area
/// cannot: it owns the whole region, and the page stops scrolling for as long as
/// any surface is up.
struct AetherDismissSurface: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> DismissView {
        let view = DismissView()
        view.action = action
        return view
    }

    func updateNSView(_ view: DismissView, context: Context) {
        view.action = action
    }

    final class DismissView: NSView {
        var action: (() -> Void)?
        /// The event being dispatched, read from AppKit by default. Settable so
        /// the rule below can be checked without a live event.
        var currentEventType: () -> NSEvent.EventType? = { NSApp.currentEvent?.type }

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch currentEventType() {
            case .leftMouseDown, .rightMouseDown: return super.hitTest(point)
            default: return nil
            }
        }

        override func mouseDown(with event: NSEvent) { action?() }

        override func rightMouseDown(with event: NSEvent) { action?() }
    }
}
