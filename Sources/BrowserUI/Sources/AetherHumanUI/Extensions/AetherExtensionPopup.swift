import AppKit
import WebKit

/// An extension's popup, in a popover of the browser's own.
///
/// The page is loaded here, in a view built from the extension's own
/// configuration, from the address the popup actually has: WebKit's popup
/// machinery is only asked *which* page the button would show (see
/// `AetherExtensions.press`). A popup that goes through WebKit's own popup
/// first, and is then replaced by this one, has already lost the first
/// messages to its worker and never renders — which is what a blank popover
/// over the toolbar was.
///
/// Chrome sizes a popup to its content, between 25 and 800 points wide and up
/// to 600 tall; the page is measured once it has loaded and again while it
/// builds itself, and the popover follows. `window.close()` closes it.
@MainActor
final class AetherExtensionPopup: NSObject, WKUIDelegate, WKNavigationDelegate, NSPopoverDelegate {
    private var popover: NSPopover?
    private var webView: WKWebView?
    private var page: AetherExtensionPopupTab?
    private var controller: WKWebExtensionController?
    private var measuring: Timer?
    private var ticks = 0
    private var shown = false
    /// The button the popup hangs from, so a press on it can be told from a
    /// press anywhere else when the popover closes.
    private weak var button: NSView?
    /// The popup a press on its own button just closed: the popover can go on
    /// mouse-down, before the button's press arrives, and would then be opened
    /// again by it.
    private var closedByButton: (id: String, at: Date)?
    private static var lastSize: [String: NSSize] = [:]
    private(set) var extensionID: String?

    func show(_ url: URL, context: WKWebExtensionContext, owner: AetherExtensions,
              window: BrowserWindowModel, profileID: UUID, anchor: NSView?) {
        close()
        guard let configuration = context.webViewConfiguration,
              let controller = owner.controller(profileID: profileID) else { return }
        let size = Self.lastSize[context.uniqueIdentifier] ?? NSSize(width: 360, height: 240)
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 25, height: 25), configuration: configuration)
        web.uiDelegate = self
        web.navigationDelegate = self
        // Unseen until the page has been measured: a popup shown at the last
        // size it had, then resized, is what makes one flash and jump.
        web.alphaValue = 0
        web.load(URLRequest(url: url))

        let stage = NSView(frame: NSRect(origin: .zero, size: size))
        stage.addSubview(web)
        let host = NSViewController()
        host.view = stage
        // The popover takes its size from its view controller: left at zero it
        // comes in as a sliver and grows, instead of standing at the size it
        // was given from the start.
        host.preferredContentSize = size

        let popover = NSPopover()
        popover.contentViewController = host
        popover.contentSize = size
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let page = AetherExtensionPopupTab(webView: web, owner: owner, window: window,
                                           profileID: profileID, extensionID: context.uniqueIdentifier)
        self.popover = popover
        self.webView = web
        self.page = page
        self.controller = controller
        self.extensionID = context.uniqueIdentifier
        self.button = (anchor?.window) != nil ? anchor : nil
        controller.didOpenTab(page)

        if let anchor, anchor.window != nil {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        } else if let content = window.nativeWindow?.contentView {
            // No button to hang from — the extension is not pinned to the
            // toolbar: where its button would be, the drawer's own corner.
            let bounds = content.bounds, flipped = content.isFlipped
            let column = window.arrangement == .sidebar
            let spot = column
                ? NSRect(x: bounds.minX + 24, y: flipped ? bounds.maxY - 24 : bounds.minY + 24, width: 1, height: 1)
                : NSRect(x: bounds.maxX - 60, y: flipped ? bounds.minY + 40 : bounds.maxY - 40, width: 1, height: 1)
            popover.show(relativeTo: spot, of: content, preferredEdge: column ? .maxX : (flipped ? .maxY : .minY))
        }

        // Measured while it loads, and for a while after, for a page that
        // builds its content from a reply to its worker.
        measuring = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.ticks += 1
                self.measure()
                if self.ticks >= 24 { timer.invalidate(); self.measuring = nil }
            }
        }
        // Shown regardless after a moment, for a page slow to load or to answer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak popover] in
            guard let self, let popover, popover === self.popover else { return }
            self.reveal()
        }
    }

    /// A press on the button of the extension whose popup is up closes it, as
    /// in Chrome — whether the popover is still there (a click on the toolbar
    /// does not close it) or went on this press's mouse-down. Closed, it must
    /// not be opened again by the press that closed it.
    func closes(_ id: String) -> Bool {
        defer { closedByButton = nil }
        if popover != nil, extensionID == id {
            close()
            return true
        }
        guard let closed = closedByButton, closed.id == id else { return false }
        return Date().timeIntervalSince(closed.at) < 1.5
    }

    func close() {
        measuring?.invalidate()
        measuring = nil
        let oldPopover = popover
        forget()
        oldPopover?.performClose(nil)
    }

    private func forget() {
        if let page { controller?.didCloseTab(page, windowIsClosing: false) }
        page = nil
        controller = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        popover = nil
        button = nil
        extensionID = nil
        shown = false
        ticks = 0
    }

    /// The page as laid out at the size it was measured at, in view.
    private func reveal() {
        guard !shown, let webView, let popover else { return }
        shown = true
        let size = popover.contentSize
        webView.frame = NSRect(origin: .zero, size: size)
        webView.autoresizingMask = [.width, .height]
        popover.contentViewController?.view.setFrameSize(size)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            webView.animator().alphaValue = 1
        }
    }

    private func measure() {
        guard let webView, let popover else { return }
        webView.evaluateJavaScript(Self.sizingExpression) { [weak self, weak webView, weak popover] value, _ in
            MainActor.assumeIsolated {
                guard let self, let webView, let popover,
                      webView === self.webView, popover === self.popover,
                      let pair = value as? [Double], pair.count == 2 else { return }
                var width = min(800, max(25, pair[0]))
                var height = min(600, max(25, pair[1]))
                // Once it is up it only grows, so a page that settles cannot
                // set it rocking.
                if self.shown && self.ticks > 8 {
                    width = max(popover.contentSize.width, width)
                    height = max(popover.contentSize.height, height)
                }
                self.apply(NSSize(width: width, height: height))
                self.reveal()
            }
        }
    }

    private func apply(_ size: NSSize) {
        guard let popover, let webView else { return }
        if abs(popover.contentSize.width - size.width) > 1 || abs(popover.contentSize.height - size.height) > 1 {
            popover.contentViewController?.preferredContentSize = size
            popover.contentSize = size
            popover.contentViewController?.view.setFrameSize(size)
            if shown { webView.frame = NSRect(origin: .zero, size: size) }
        }
        Self.lastSize[extensionID ?? ""] = size
        reveal()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        measure()
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        close()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, let page, let window = page.window {
            window.navigateExtension(window.newTab(), to: url)
        }
        close()
        return nil
    }

    func popoverWillClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === popover, let id = extensionID,
              let button, let window = button.window, let event = NSApp.currentEvent,
              event.window === window,
              event.type == .leftMouseDown || event.type == .leftMouseUp else { return }
        if button.bounds.contains(button.convert(event.locationInWindow, from: nil)) {
            closedByButton = (id, Date())
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === popover else { return }
        measuring?.invalidate()
        measuring = nil
        forget()
    }

    /// The size Chrome would give the popup (Blink's auto-size, between
    /// 25 × 25 and 800 × 600), worked out in the page while its view is still
    /// the 25-point square: the width the page names for itself if it names
    /// one, else its narrowest (min-content — what is positioned off to the
    /// side doesn't count), else, for a page with next to no width of its own,
    /// what its content spans; then, laid out at that width, the height it
    /// names or spans. Nothing of it is left on the page.
    static let preferredSize = #"""
    () => {
      const d = document.documentElement;
      if (!d) return null;
      const m = window.__aetherSizing || (window.__aetherSizing = {});
      const saved = d.getAttribute("style");
      const restore = () => saved === null ? d.removeAttribute("style") : d.setAttribute("style", saved);
      const box = d.getBoundingClientRect();
      let w;
      if (Math.abs(box.width - innerWidth) > 1) w = m.w = box.width;
      else if (m.w && Math.abs(m.w - innerWidth) <= 1) w = m.w;
      else {
        d.style.setProperty("width", "min-content", "important");
        const narrowest = d.getBoundingClientRect().width;
        restore();
        w = narrowest >= 100 ? narrowest : Math.max(narrowest, d.scrollWidth);
      }
      w = Math.min(800, Math.max(25, Math.ceil(w)));
      d.style.setProperty("width", w + "px", "important");
      let h = d.getBoundingClientRect().height;
      if (Math.abs(h - innerHeight) > 1) m.h = h;
      else if (m.h && Math.abs(m.h - innerHeight) <= 1) h = m.h;
      else {
        d.style.setProperty("height", "auto", "important");
        d.style.setProperty("min-height", "0", "important");
        h = d.getBoundingClientRect().height;
      }
      restore();
      return [w, Math.min(600, Math.max(25, Math.ceil(h)))];
    }
    """#

    /// What the popup's page is asked for its size with. It has to be the
    /// call: the script is an arrow function, and one evaluated on its own
    /// answers with nothing — a popup that is never answered is never sized
    /// and never revealed, which is a blank popover over the toolbar.
    static var sizingExpression: String { "(\(preferredSize))()" }
}

@MainActor
private final class AetherExtensionPopupTab: NSObject, WKWebExtensionTab {
    weak var webView: WKWebView?
    weak var owner: AetherExtensions?
    weak var window: BrowserWindowModel?
    let profileID: UUID
    let extensionID: String

    init(webView: WKWebView, owner: AetherExtensions, window: BrowserWindowModel,
         profileID: UUID, extensionID: String) {
        self.webView = webView
        self.owner = owner
        self.window = window
        self.profileID = profileID
        self.extensionID = extensionID
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard let owner, let window else { return nil }
        return owner.windowAdapter(for: window, profileID: profileID)
    }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { NSNotFound }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func title(for context: WKWebExtensionContext) -> String? { webView?.title }
    func url(for context: WKWebExtensionContext) -> URL? { webView?.url }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !(webView?.isLoading ?? false) }
    func isSelected(for context: WKWebExtensionContext) -> Bool { false }
    func close(for context: WKWebExtensionContext) async throws { owner?.closePopup(extensionID) }
}
