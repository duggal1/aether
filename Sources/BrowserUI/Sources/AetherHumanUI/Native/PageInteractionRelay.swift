import AppKit
import WebKit

// Adapted from Search's HoveredLink and MiddleRelay. The scripts run beside
// the page in WebKit's isolated client world.
@MainActor
final class PageInteractionRelay: NSObject, WKScriptMessageHandler {
    private static let linkName = "aetherHoveredLink"
    private static let middleName = "aetherMiddleLink"
    private static let appearanceName = "aetherAppearanceTick"
    private weak var window: BrowserWindowModel?
    private weak var view: WKWebView?
    private let pageID: String
    private var hiding: DispatchWorkItem?

    private init(pageID: String, view: WKWebView, window: BrowserWindowModel) {
        self.pageID = pageID
        self.view = view
        self.window = window
    }

    static func install(on view: WKWebView, pageID: String, window: BrowserWindowModel) -> PageInteractionRelay {
        let relay = PageInteractionRelay(pageID: pageID, view: view, window: window)
        let controller = view.configuration.userContentController
        controller.add(relay, contentWorld: .defaultClient, name: linkName)
        controller.add(relay, contentWorld: .defaultClient, name: middleName)
        controller.add(relay, contentWorld: .defaultClient, name: appearanceName)
        let linkScript = WKUserScript(source: hoverScript, injectionTime: .atDocumentStart,
                                      forMainFrameOnly: false, in: .defaultClient)
        let middleScript = WKUserScript(source: Self.middleScript, injectionTime: .atDocumentStart,
                                        forMainFrameOnly: true, in: .defaultClient)
        let appearanceScript = WKUserScript(source: Self.appearanceScript, injectionTime: .atDocumentStart,
                                            forMainFrameOnly: true, in: .defaultClient)
        controller.addUserScript(linkScript)
        controller.addUserScript(middleScript)
        controller.addUserScript(appearanceScript)
        view.evaluateJavaScript(hoverScript, in: nil, in: .defaultClient) { _ in }
        view.evaluateJavaScript(Self.middleScript, in: nil, in: .defaultClient) { _ in }
        view.evaluateJavaScript(Self.appearanceScript, in: nil, in: .defaultClient) { _ in }
        return relay
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === view, let window,
              window.selected?.enginePageID == pageID else { return }
        if message.name == Self.linkName, let address = message.body as? String {
            hiding?.cancel()
            if address.isEmpty {
                let work = DispatchWorkItem { [weak window] in window?.hoveredLink = nil }
                hiding = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            } else {
                window.hoveredLink = address
                if let view, let host = view.window {
                    let point = view.convert(host.mouseLocationOutsideOfEventStream, from: nil)
                    let bottom = view.isFlipped ? view.bounds.height - point.y : point.y
                    window.linkPreviewOnRight = bottom < 50 && point.x < min(view.bounds.width * 0.6, 640) + 22
                }
            }
        } else if message.name == Self.middleName, message.frameInfo.isMainFrame,
                  let address = message.body as? String, let url = URL(string: address),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            _ = window.newTab(url: url.absoluteString, select: false)
        } else if message.name == Self.appearanceName, message.frameInfo.isMainFrame {
            // §§6–7 realtime path: the visible region meaningfully changed
            // (scrolled, resized, DOM/theme mutation). Throttled inside the
            // controller; DOM sampling only, never screenshots.
            guard let tab = window.selected, tab.enginePageID == pageID,
                  let webView = view else { return }
            let systemDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            WebsiteAppearanceController.shared.requestTick(tab: tab, webView: webView, systemDark: systemDark)
        }
    }

    // Search/StatusLine.swift: resolved anchors and image-map links, including
    // open shadow trees, with no stale value after leaving a frame.
    private static let hoverScript = """
    (() => {
      if (window.__aetherLinks) return;
      window.__aetherLinks = true;
      let shown = '';
      function report(address) {
        if (address === shown) return;
        shown = address;
        webkit.messageHandlers.aetherHoveredLink.postMessage(address);
      }
      function linkIn(path) {
        for (const node of path) {
          if (node.nodeType !== 1 || (node.localName !== 'a' && node.localName !== 'area')) continue;
          const href = typeof node.href === 'string' ? node.href : node.href && node.href.baseVal;
          if (!href) continue;
          try {
            const address = new URL(href, node.baseURI).href;
            return address.startsWith('javascript:') ? '' : address.slice(0, 600);
          } catch { return ''; }
        }
        return '';
      }
      addEventListener('mouseover', event => report(linkIn(event.composedPath())), { passive: true, capture: true });
      addEventListener('mouseout', event => { if (!event.relatedTarget) report(''); }, { passive: true, capture: true });
      addEventListener('pagehide', () => report(''));
    })();
    """

    // Search/Tab.swift MiddleRelay: let the page's own auxclick handler run
    // before deciding whether it left an unclaimed middle click for the browser.
    private static let middleScript = """
    (() => {
      if (window.__aetherMiddle) return;
      window.__aetherMiddle = true;
      document.addEventListener('auxclick', event => {
        if (event.button !== 1 || !event.isTrusted || event.defaultPrevented) return;
        for (const node of event.composedPath()) {
          const tag = node.tagName ? node.tagName.toLowerCase() : '';
          if (tag !== 'a' && tag !== 'area') continue;
          const href = typeof node.href === 'string' ? node.href : node.href && node.href.baseVal;
          if (!href) continue;
          try { webkit.messageHandlers.aetherMiddleLink.postMessage(new URL(href, node.baseURI).href); } catch (_) {}
          return;
        }
      });
    })();
    """

    // §§6–7 realtime trigger: scroll / resize / DOM-background / theme
    // changes. Throttled in-page (rAF + 800ms + 60px) AND natively (0.7s per
    // page in WebsiteAppearanceController), DOM sampling only — never
    // screenshots, never per-frame.
    private static let appearanceScript = """
    (() => {
      if (window.__aetherAppearance) return;
      window.__aetherAppearance = true;
      let lastSent = 0;
      let lastY = window.scrollY || 0;
      let ticking = false;
      function tick(reason) {
        const now = Date.now();
        const y = window.scrollY || 0;
        if (reason === 'scroll' && now - lastSent < 800 && Math.abs(y - lastY) < 60) { ticking = false; return; }
        ticking = false;
        lastSent = now;
        lastY = y;
        try { webkit.messageHandlers.aetherAppearanceTick.postMessage(reason); } catch (_) {}
      }
      function request(reason) {
        if (ticking) return;
        ticking = true;
        requestAnimationFrame(() => tick(reason));
      }
      addEventListener('scroll', () => request('scroll'), { passive: true, capture: true });
      addEventListener('resize', () => request('resize'), { passive: true });
      const media = matchMedia && matchMedia('(prefers-color-scheme: dark)');
      if (media && media.addEventListener) media.addEventListener('change', () => request('theme'));
      let mutationQueued = false;
      const observer = new MutationObserver(() => {
        if (mutationQueued) return;
        mutationQueued = true;
        setTimeout(() => { mutationQueued = false; request('dom'); }, 900);
      });
      const start = () => {
        try {
          if (document.documentElement) observer.observe(document.documentElement, { attributes: true, attributeFilter: ['style', 'class', 'color-scheme'] });
          if (document.body) observer.observe(document.body, { attributes: true, attributeFilter: ['style', 'class'] });
        } catch (_) {}
      };
      if (document.readyState === 'loading') addEventListener('DOMContentLoaded', start, { once: true });
      else start();
    })();
    """
}
