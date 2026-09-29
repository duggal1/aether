import AppKit
import EngineCore
import WebKit

/// Hosts page views in an offscreen `NSWindow`.
///
/// A `WKWebView` that is not in a window reports `document.visibilityState === "hidden"`
/// and cannot receive native input. Both are fatal for agent work:
///
/// * Content-visibility-gated UIs (YouTube's feed renders on visibility and
///   `IntersectionObserver`) never paint at all — the page is present in the DOM but
///   permanently empty.
/// * `canSendNativePointer()` is `view.window != nil`, so every click degrades to a
///   synthetic `MouseEvent` with `isTrusted == false`. That removes user activation, which
///   `window.open()` requires, so OAuth popups cannot open.
///
/// `orderBack` is required: WebKit only treats a view as visible once its window is ordered
/// in, not merely allocated.
@MainActor
enum OffscreenPageHost {
    /// One window per page. A single shared window would make every page except the front
    /// one occluded, and macOS throttles occluded views — exactly the failure this type
    /// exists to remove.
    static func makeWindow(for pageID: PageID) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.alphaValue = 1
        window.setFrameOrigin(NSPoint(x: -20_000 - CGFloat(pageID.rawValue) * 40, y: -20_000))
        // Ordered in, not just created. This is what flips `visibilityState` to "visible".
        window.orderBack(nil)
        windows[ObjectIdentifier(window)] = window
        return window
    }

    /// Keeps windows alive for the process lifetime; WebKit holds the returned view only as
    /// long as the window does.
    nonisolated(unsafe) private static var windows: [ObjectIdentifier: NSWindow] = [:]

    /// Attaches `view` to a fresh offscreen window. A no-op when the view is already hosted
    /// (the human-facing app puts it in a real window).
    static func attach(_ view: WKWebView, pageID: PageID) {
        guard view.window == nil else { return }
        let window = makeWindow(for: pageID)
        view.frame = window.contentLayoutRect
        window.contentView?.addSubview(view)
    }

    static func resize(_ view: WKWebView, pageID: PageID) {
        guard let window = view.window else { return }
        view.frame = window.contentLayoutRect
    }

    static func detach(_ view: WKWebView) {
        guard let window = view.window else { return }
        view.removeFromSuperview()
        windows[ObjectIdentifier(window)] = nil
        window.orderOut(nil)
    }
}
