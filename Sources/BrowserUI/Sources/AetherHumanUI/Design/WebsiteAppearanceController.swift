import AppKit
import WebKit

// Correction pass §§6–7, §17: the ONE website-surface detector.
//
// Every floating card (Search Tabs, History, Bookmarks, Extensions, profile /
// space menu, Reader, suggestions, three-dot menu) already consumes the single
// resolved `aetherSurfaceStyle`. This controller is the single place that
// *produces* the value it resolves from: it samples the currently visible
// webpage region via DOM (never screenshots, never per-frame), converts to
// luminance, applies hysteresis, and publishes only when the mode changes.
//
// Triggers: navigation completed + tab switched + window restored arrive via
// BrowserWindowView.syncAppearance (delayed re-reads after paint); meaningful
// scroll / DOM / theme changes arrive via PageInteractionRelay ticks below.
// Both paths funnel through `update(tab:webView:systemDark:)` here, so the
// sampling script, the parse and the hysteresis can never drift apart.
//
// The spec's `WebsiteSurfaceAppearance.light/dark` model is represented by
// `AetherSurfaceAppearance.lightWebsite/darkWebsite` (plus `.homepage` for
// browser-drawn pages such as New Tab, which have no website tone to sample).
// One detector. One palette resolver (`AetherSurfaceResolver`). All overlays.
@MainActor
public final class WebsiteAppearanceController {
    public static let shared = WebsiteAppearanceController()

    /// Minimum gap between two scroll/DOM-triggered samples for one page.
    /// Navigation-triggered samples bypass this; scrolling never bypasses it,
    /// so a fast fling cannot queue expensive evaluations.
    private static let tickInterval: TimeInterval = 0.7
    /// A scroll tick only counts when the viewport moved this far since the
    /// last accepted tick — enforced in JS, mirrored here by the time gate.
    private var lastTick: [String: Date] = [:]

    private init() {}

    public struct PageAppearanceReading {
        public let surface: UInt?
        public let declaresDark: Bool?
        public init(surface: UInt?, declaresDark: Bool?) {
            self.surface = surface
            self.declaresDark = declaresDark
        }
        public var settled: Bool { surface != nil || declaresDark != nil }
    }

    /// One definition of "browser-drawn page". Mirrors BrowserWindowView's
    /// rule: New Tab / search / failure have no website tone to sample, and a
    /// loading page without a URL has nothing to sample yet.
    public static func isBrowserPage(_ tab: BrowserTab) -> Bool {
        switch tab.loadState {
        case .newTab, .search(_), .failed(_): return true
        case .loading, .ready: return tab.url == nil
        }
    }

    /// The DOM sampler. Several points, not one: a transparent header is
    /// common, and a single sample near the top used to miss the page
    /// entirely. Gradients/photos are skipped (the layer underneath is usually
    /// the page's real colour); `color-scheme` is read as a second signal.
    /// Cheap by design — elementFromPoint + computed style, no screenshots.
    public static let samplingScript = """
    (() => {
      const parse = (value) => {
        const m = /^rgba?\\(\\s*(\\d+)\\s*[, ]\\s*(\\d+)\\s*[, ]\\s*(\\d+)(?:\\s*[,/]\\s*([\\d.]+))?\\s*\\)$/.exec(value);
        if (!m) return null;
        const alpha = m[4] === undefined ? 1 : Number(m[4]);
        if (!(alpha > 0.9)) return null;
        return '#' + [m[1], m[2], m[3]]
          .map(x => Number(x).toString(16).padStart(2, '0')).join('');
      };
      // Walk the ancestor chain from one point on the page.
      const backdrop = (x, y) => {
        let node = document.elementFromPoint(x, y);
        for (; node; node = node.parentElement) {
          const style = getComputedStyle(node);
          // A gradient or a photo is not a tone we can read. Keep walking:
          // the layer underneath it is usually the page's real colour.
          if (style.backgroundImage && style.backgroundImage !== 'none') continue;
          const found = parse(style.backgroundColor);
          if (found) return found;
        }
        return null;
      };
      const scheme = (value) => {
        const v = (value || '').toLowerCase();
        if (v.includes('dark') && !v.includes('light')) return true;
        if (v.includes('light') && !v.includes('dark')) return false;
        return null;
      };
      const w = Math.max(1, innerWidth);
      const h = Math.max(1, innerHeight);
      // Several points. A transparent header is common, and a single sample
      // near the top of the viewport used to miss the page entirely.
      let hex = backdrop(w / 2, h / 2)
        || backdrop(w / 2, 8)
        || backdrop(w / 4, h / 3)
        || backdrop(w / 2, h - 8)
        || backdrop(0, 0);
      if (!hex) {
        hex = parse(getComputedStyle(document.documentElement).backgroundColor)
          || parse(getComputedStyle(document.body).backgroundColor);
      }
      const meta = document.querySelector('meta[name="color-scheme"]');
      const declared = scheme(getComputedStyle(document.documentElement).colorScheme)
        ?? scheme(document.documentElement.style.colorScheme)
        ?? scheme(meta && meta.content);
      return [hex, declared];
    })()
    """

    public static func parse(payload: [Any]) -> PageAppearanceReading? {
        guard payload.count == 2 else { return nil }
        let hexString = payload[0] as? String
        return PageAppearanceReading(
            surface: hexString.flatMap { $0.hasPrefix("#") ? UInt($0.dropFirst(), radix: 16) : nil },
            declaresDark: (payload[1] as? NSNumber)?.boolValue)
    }

    /// Write a reading into the tab. Luminance + hysteresis live in
    /// `AetherSurfaceResolver`; `surfaceAppearance` is only assigned when the
    /// mode actually changes, so views don't churn while a page sits near the
    /// threshold.
    public func apply(_ reading: PageAppearanceReading, to tab: BrowserTab, systemDark: Bool) {
        tab.siteSurface = reading.surface
        tab.sitePrefersDark = reading.declaresDark
        let next = AetherSurfaceResolver.appearance(
            for: AetherPageSnapshot(isBrowserPage: Self.isBrowserPage(tab),
                                    surface: reading.surface,
                                    declaresDark: reading.declaresDark),
            systemDark: systemDark,
            current: tab.surfaceAppearance)
        if tab.surfaceAppearance != next {
            tab.surfaceAppearance = next
        }
    }

    /// Sample one web view and apply. Returns true when the page said
    /// something (surface or declared scheme) — navigation callers use that
    /// as "settled, no further delayed pass needed".
    @discardableResult
    public func update(tab: BrowserTab, webView: WKWebView, systemDark: Bool) async -> Bool {
        let expectedURL = tab.url
        guard let payload = (try? await webView.evaluateJavaScript(Self.samplingScript)) as? [Any],
              !Task.isCancelled, tab.url == expectedURL,
              let reading = Self.parse(payload: payload) else { return false }
        apply(reading, to: tab, systemDark: systemDark)
        return reading.settled
    }

    /// Scroll / DOM / theme-change entry point. Throttled per page; drops
    /// browser-drawn pages (nothing to sample) and stale tabs.
    public func requestTick(tab: BrowserTab, webView: WKWebView, systemDark: Bool) {
        guard let pageID = tab.enginePageID, !Self.isBrowserPage(tab) else { return }
        let now = Date()
        if let last = lastTick[pageID], now.timeIntervalSince(last) < Self.tickInterval { return }
        lastTick[pageID] = now
        if lastTick.count > 256 { lastTick.removeValue(forKey: lastTick.keys.first!) }
        Task { [weak webView] in
            guard let webView, !Task.isCancelled else { return }
            _ = await self.update(tab: tab, webView: webView, systemDark: systemDark)
        }
    }
}
