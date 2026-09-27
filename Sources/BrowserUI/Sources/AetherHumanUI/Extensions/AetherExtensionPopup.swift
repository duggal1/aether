import AppKit
import WebKit

@MainActor
final class AetherExtensionPopup: NSObject, WKUIDelegate, WKNavigationDelegate, NSPopoverDelegate {
    private var popover: NSPopover?
    private var webView: WKWebView?
    private var page: AetherExtensionPopupTab?
    private var controller: WKWebExtensionController?
    private var measuring: Timer?
    private var ticks = 0
    private var shown = false
    private static var lastSize: [String: NSSize] = [:]
    private(set) var extensionID: String?

    func show(_ url: URL, context: WKWebExtensionContext, owner: AetherExtensions,
              window: BrowserWindowModel, profileID: UUID, anchor: NSView) {
        close()
        guard let configuration = context.webViewConfiguration,
              let controller = owner.controller(profileID: profileID) else { return }
        let size = Self.lastSize[context.uniqueIdentifier] ?? NSSize(width: 360, height: 240)
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 25, height: 25), configuration: configuration)
        web.uiDelegate = self
        web.navigationDelegate = self
        web.alphaValue = 0
        let stage = NSView(frame: NSRect(origin: .zero, size: size))
        stage.addSubview(web)
        let host = NSViewController()
        host.view = stage
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
        controller.didOpenTab(page)

        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        // From a copy under another name, never the popup's own path: WebKit
        // takes any page at an extension's popup path for its own popup, and
        // a popup in another view is sent no events and renders nothing.
        web.load(URLRequest(url: AetherExtensions.unpopped(url, context: context)))
        measuring = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.ticks += 1
                self.measure()
                if self.ticks >= 24 { timer.invalidate(); self.measuring = nil }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak popover] in
            guard let self, let popover, popover === self.popover else { return }
            self.reveal()
        }
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
        extensionID = nil
        shown = false
        ticks = 0
    }

    private func measure() {
        guard let webView, let popover else { return }
        webView.evaluateJavaScript(Self.preferredSize) { [weak self, weak webView, weak popover] value, _ in
            MainActor.assumeIsolated {
                guard let self, let webView, let popover,
                      webView === self.webView, popover === self.popover,
                      let pair = value as? [Double], pair.count == 2 else { return }
                var width = min(800, max(25, pair[0]))
                var height = min(600, max(25, pair[1]))
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
        }
        Self.lastSize[extensionID ?? ""] = size
        webView.frame = NSRect(origin: .zero, size: size)
        webView.autoresizingMask = [.width, .height]
    }

    private func reveal() {
        guard !shown, let webView else { return }
        shown = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            webView.animator().alphaValue = 1
        }
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
        if let url = navigationAction.request.url, let page {
            let tab = page.window?.newTab()
            if let tab { page.window?.navigateExtension(tab, to: url) }
        }
        close()
        return nil
    }

    func popoverDidClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === popover else { return }
        measuring?.invalidate()
        measuring = nil
        forget()
    }

    private static let preferredSize = #"""
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
