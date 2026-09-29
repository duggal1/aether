import AppKit
import BrowserEvents
import DOM
import EngineCore
import Foundation
import Network
import Networking
import WebKit

@MainActor
final class WebKitStoreCache {
  static let shared = WebKitStoreCache()
  private var named: [UUID: WKWebsiteDataStore] = [:]

  func store(for identifier: UUID?) -> WKWebsiteDataStore {
    guard let identifier else { return WKWebsiteDataStore.nonPersistent() }
    if let existing = named[identifier] { return existing }
    let created = WKWebsiteDataStore(forIdentifier: identifier)
    named[identifier] = created
    return created
  }

  func purge(_ identifier: UUID) async {
    guard let store = named[identifier] else { return }
    await store.removeData(
      ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    named[identifier] = nil
  }
}

extension BrowserRuntime {
  func purgeWebKitStore(identifier: UUID) async {
    await WebKitStoreCache.shared.purge(identifier)
  }
}

public struct WebProxyEndpoint: Sendable, Equatable {
  public let host: String
  public let port: UInt16
  public let username: String?
  public let password: String?
  public let failClosed: Bool

  public init(host: String, port: UInt16, username: String? = nil, password: String? = nil,
    failClosed: Bool = true) {
    self.host = host
    self.port = port
    self.username = username
    self.password = password
    self.failClosed = failClosed
  }

  public static let failClosedBlackhole = WebProxyEndpoint(host: "127.0.0.1", port: 9, failClosed: true)
}

extension BrowserRuntime {
  func webPage(_ id: PageID) async throws -> WebKitPage {
    let record = try requirePage(id)
    guard record.lifecycle != .discarded else {
      throw BrowserRuntimeError.invalidState("Page is discarded; restore it before use")
    }
    if let page = webPages[id] { return page }
    if let task = webPageTasks[id] { return await task.value }
    WebKitNavigationProbe.log("webPage.miss id=\(id)")
    let identifier = webProfileIdentifiers[record.contextID]
    let wantEphemeral = webEphemeral.contains(record.contextID)
    let context: WebKitContext
    if let existing = webContexts[record.contextID], existing.isEphemeral == wantEphemeral {
      context = existing
    } else {
      let fresh: WebKitContext
      if wantEphemeral {
        fresh = await WebKitContext.ephemeral()
        webEphemeralStores[record.contextID] = fresh.store
      } else if let identifier {
        fresh = await WebKitContext(identifier: identifier)
      } else {
        throw BrowserRuntimeError.invalidState(
          "Profile identifier is missing for a permanent context")
      }
      let stored = webContextRules[record.contextID] as? WKContentRuleList
      let pendingProxy = webProxyEndpoints[record.contextID]
      await MainActor.run {
        fresh.rules = stored
        if let pendingProxy { fresh.apply(proxy: pendingProxy) }
      }
      webContexts[record.contextID] = fresh
      context = fresh
    }
    if let page = webPages[id] { return page }
    if let pending = webPageTasks[id] {
      let page = await pending.value
      await applyPreparedPresentationPolicy(to: page, pageID: id)
      return page
    }
    let viewport = record.viewport
    let relay = pageEventChannel.continuation
    let eventPageID = id
    let task = Task { @MainActor [weak self] in
      let page = WebKitPage(context: context, viewport: viewport,
        fileUploadRequested: { [weak self] upload in
          Task { await self?.classifyFileUpload(pageID: id, context: upload) }
        },
        emitEvent: { kind in relay.yield((eventPageID, kind)) },
        popupOpened: { [weak self] popup in
          // A popup is a real page an agent must be able to drive: Google's GSI account
          // chooser lives entirely inside the child window, so without registration the
          // OAuth flow can never be completed by an agent.
          Task { await self?.adoptPopup(popup, opener: id) }
        }
      ) { [weak self] state in
          Task { await self?.receiveWebState(state, pageID: id) }
        }
      // No on-screen window exists in the headless daemon. Without one the view reports
      // `visibilityState === "hidden"` (content-visibility-gated UIs never paint) and
      // cannot receive native input, so every click degrades to `isTrusted == false`.
      if page.view.window == nil { OffscreenPageHost.attach(page.view, pageID: id) }
      return page
    }
    webPageTasks[id] = task
    let page = await task.value
    WebKitNavigationProbe.log("webPage.ready id=\(id)")
    webPageTasks[id] = nil
    guard contextID(containing: id) != nil else {
      await page.close()
      webPagesPreparedForPresentation.remove(id)
      throw BrowserRuntimeError.pageNotFound(id)
    }
    webPages[id] = page
    webContexts[record.contextID] = page.context
    await applyPreparedPresentationPolicy(to: page, pageID: id)
    return page
  }

  private func applyPreparedPresentationPolicy(to page: WebKitPage, pageID: PageID) async {
    guard webPagesPreparedForPresentation.remove(pageID) != nil else { return }
    await page.prepareForPresentation()
  }

  public func webSurface(pageID: PageID) async throws -> WKWebView {
    return try await webPage(pageID).view
  }

  public func isWebContentLive(pageID: PageID) -> Bool { webPages[pageID] != nil }

  public func prepareWebPageForPresentation(pageID: PageID) async throws {
    _ = try requirePage(pageID)
    guard let page = webPages[pageID] else {
      webPagesPreparedForPresentation.insert(pageID)
      return
    }
    await page.prepareForPresentation()
  }

  public func warmProfileStore(contextID: ContextID) async throws {
    let context = try await webContextForCookies(contextID)
    await MainActor.run { WebKitPrewarm.warmProfileStore(context) }
  }

  func restoreWebContent(_ id: PageID) async throws {
    guard webPages[id] == nil else { return }
    let record = try requirePage(id)
    let target = webStates[id]?.url
      ?? (record.history.indices.contains(record.historyIndex) ? record.history[record.historyIndex] : nil)
    let page = try await webPage(id)
    if let html = record.lastHTML {
      let url = target ?? URL(string: "https://localhost/")!
      try await page.loadHTML(html, url: url)
      _ = try await synchronizedWebInfo(id)
    } else if let target {
      _ = try await navigateWeb(pageID: id, request: HTTPRequest(url: target))
    }
  }

  func receiveWebState(_ state: WebPageState, pageID: PageID) {
    guard let contextID = contextID(containing: pageID),
      var page = contexts[contextID]?.pages[pageID],
      state.sequence > (webStates[pageID]?.sequence ?? 0) else { return }
    let previous = webStates[pageID]
    webStates[pageID] = state
    if state.loaded, let previousURL = previous?.url, previousURL != state.url {
      page.lastHTML = nil
    }
    let viewportChanged = previous?.viewport != state.viewport
    let historyChanged =
      previous?.history != state.history ||
      previous?.historyIndex != state.historyIndex
    let currentHistoryURL = page.history.indices.contains(page.historyIndex)
      ? page.history[page.historyIndex] : nil
    let shouldRecordDocumentURL =
      state.loaded && state.history.isEmpty && state.url != nil && currentHistoryURL != state.url
    guard viewportChanged || historyChanged || shouldRecordDocumentURL else {
      publishPageState(pageID)
      return
    }
    if viewportChanged {
      page.viewport = state.viewport
    }
    if historyChanged, !state.history.isEmpty {
      page.history = state.history
      page.historyIndex = state.historyIndex
    } else if shouldRecordDocumentURL, let url = state.url {
      // `loadHTMLString` has a base URL but WebKit may not add it to its
      // back-forward list. Keep the current document address available to
      // Aether's persisted history/session APIs without inventing an HTTP
      // response for the synthetic document.
      if page.historyIndex + 1 < page.history.count {
        page.history.removeSubrange((page.historyIndex + 1)..<page.history.count)
      }
      page.history.append(url)
      page.historyIndex = page.history.count - 1
    }
    updatePageRecord(page)
  }

  func synchronizedWebInfo(_ id: PageID) async throws -> BrowserPageInfo {
    let page = try await webPage(id)
    let state = await page.state()
    receiveWebState(state, pageID: id)
    var info = try pageInfo(id)
    if state.loaded, info.title.isEmpty,
      let title = try? await page.decode(String.self, "JSON.stringify(document.title)")
    {
      info.title = title
    }
    return info
  }

  func navigateWeb(pageID: PageID, request: HTTPRequest, settle: PageReadiness = .complete) async throws -> BrowserPageInfo {
    let probeOn = WebKitNavigationProbe.enabled
    let start = probeOn ? Date() : nil
    let page = try await webPage(pageID)
    var native = URLRequest(url: request.url)
    native.httpMethod = request.method.rawValue
    native.allHTTPHeaderFields = request.headers
    native.httpBody = request.body
    if request.cachePolicy == .reloadIgnoringCache { native.cachePolicy = .reloadIgnoringLocalCacheData }
    do { try await page.navigate(native, settle: settle) }
    catch {
      receiveWebState(await page.state(), pageID: pageID)
      throw error
    }
    let info = try await synchronizedWebInfo(pageID)
    if let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var record = context.pages[pageID]
    {
      record.lastHTML = nil
      context.pages[pageID] = record
      contexts[contextID] = context
    }
    if let start {
      let total = Date().timeIntervalSince(start) * 1000
      let tail: String
      if let committedAt = await page.committedAt {
        tail = String(format: " commitToReturn=%.1fms", Date().timeIntervalSince(committedAt) * 1000)
      } else {
        tail = ""
      }
      WebKitNavigationProbe.log(
        String(format: "navigate total=%.1fms settle=%@%@", total, String(describing: settle), tail))
    }
    return info
  }

  public func findWebText(pageID: PageID, query: String, forward: Bool) async throws -> Int {
    try await webPage(pageID).find(query, forward: forward)
  }

  public func webDocumentHTML(pageID: PageID) async throws -> String {
    try await webPage(pageID).script("document.documentElement.outerHTML")
  }

  public func webDocumentText(pageID: PageID) async throws -> String {
    try await webPage(pageID).script("document.body.innerText")
  }

  /// Clean article markdown for Reader. Not `innerText`: the live DOM is
  /// cloned, chrome/junk subtrees are removed (nav, header, footer, asides,
  /// forms, ads, share/subscribe/comment blocks, hidden nodes), the content
  /// root prefers `<article>` / `[role=main]` / `<main>`, and the remainder is
  /// converted to headings, paragraphs, lists, quotes, fenced code and links.
  /// Whitespace is collapsed and output is capped, so Reader gets an article —
  /// not the page's nav, footer and cookie banners.
  public func webReaderMarkdown(pageID: PageID) async throws -> String {
    try await webPage(pageID).script(Self.readerExtractionScript)
  }

  private static let readerExtractionScript = """
  (() => {
    const JUNK_TAGS = new Set(['SCRIPT','STYLE','NOSCRIPT','IFRAME','CANVAS','SVG','VIDEO','AUDIO','FORM','BUTTON','SELECT','INPUT','TEXTAREA','OPTION','NAV','HEADER','FOOTER','ASIDE','DIALOG']);
    const JUNK_SEL = '[role="banner"],[role="contentinfo"],[role="complementary"],[role="navigation"],[hidden],.ad,.ads,.advert,.sidebar,.menu,.nav,.navbar,.footer,.header,.cookie,.popup,.modal,.share,.sharing,.social,.subscribe,.newsletter,.related,.comments,.byline,.breadcrumb';
    const INLINE = new Set(['A','SPAN','CODE','STRONG','B','EM','I','U','SMALL','TIME','ABBR','CITE','Q','SUB','SUP','MARK','IMG','BR']);
    const root = document.querySelector('article') || document.querySelector('[role="main"]') || document.querySelector('main') || document.body;
    if (!root) return '';
    const clone = root.cloneNode(true);
    clone.querySelectorAll(JUNK_SEL).forEach(n => n.remove());
    JUNK_TAGS.forEach(t => Array.from(clone.getElementsByTagName(t)).forEach(n => n.remove()));
    const out = [];
    const clean = s => (s || '').replace(/[ \\t\\u00a0]+/g, ' ').trim();
    function inlineText(el) {
      let s = '';
      el.childNodes.forEach(n => {
        if (n.nodeType === 3) { s += n.textContent; }
        else if (n.nodeType === 1) {
          const t = n.tagName;
          if (t === 'BR') s += '\\n';
          else if (t === 'A') {
            const inner = inlineText(n).trim();
            const href = (n.getAttribute('href') || '').trim();
            s += (inner && /^https?:\\/\\//.test(href)) ? '[' + inner + '](' + href + ')' : inner;
          }
          else if (t === 'CODE') s += '`' + inlineText(n).trim() + '`';
          else if (t === 'STRONG' || t === 'B') s += '**' + inlineText(n).trim() + '**';
          else if (t === 'EM' || t === 'I') s += '*' + inlineText(n).trim() + '*';
          else if (!JUNK_TAGS.has(t)) s += inlineText(n);
        }
      });
      return s.replace(/[ \\t\\u00a0]+/g, ' ');
    }
    function blocks(el) {
      el.childNodes.forEach(n => {
        if (n.nodeType === 3) { const s = clean(n.textContent); if (s) out.push(s); return; }
        if (n.nodeType !== 1) return;
        const t = n.tagName;
        if (JUNK_TAGS.has(t) || t === 'TD' || t === 'TH') return;
        if (/^H[1-6]$/.test(t)) { const s = clean(inlineText(n)); if (s) out.push('#'.repeat(Number(t[1])) + ' ' + s); }
        else if (t === 'LI') { const s = clean(inlineText(n)); if (s) out.push('- ' + s); }
        else if (t === 'PRE') { const c = (n.textContent || '').replace(/\\n{3,}/g, '\\n\\n').trim(); if (c) out.push('```\\n' + c + '\\n```'); }
        else if (t === 'BLOCKQUOTE') { const s = clean(inlineText(n)).replace(/\\n+/g, '\\n> '); if (s) out.push('> ' + s); }
        else if (t === 'HR') out.push('---');
        else if (t === 'TR') {
          const cells = Array.from(n.children).filter(c => c.tagName === 'TD' || c.tagName === 'TH').map(c => clean(inlineText(c))).filter(Boolean);
          if (cells.length) out.push(cells.join(' | '));
        }
        else if (t === 'P' || t === 'DIV' || t === 'SECTION' || t === 'ARTICLE' || t === 'MAIN' || t === 'FIGURE' || t === 'UL' || t === 'OL' || t === 'TABLE' || t === 'TBODY') {
          const kids = Array.from(n.children);
          if (kids.length && kids.every(k => INLINE.has(k.tagName))) { const s = clean(inlineText(n)); if (s) out.push(s); }
          else blocks(n);
        }
        else { const s = clean(inlineText(n)); if (s) out.push(s); }
      });
    }
    blocks(clone);
    return out.join('\\n\\n').replace(/\\n{3,}/g, '\\n\\n').trim().slice(0, 200000);
  })()
  """

  func configureWebBlocking(contextID: ContextID, rules: String, enabled: Bool) async throws {
    let wantEphemeral = webEphemeral.contains(contextID)
    let context: WebKitContext
    if let existing = webContexts[contextID], existing.isEphemeral == wantEphemeral {
      context = existing
    } else {
      if wantEphemeral {
        context = await WebKitContext.ephemeral()
        webEphemeralStores[contextID] = context.store
      } else if let identifier = webProfileIdentifiers[contextID] {
        context = await WebKitContext(identifier: identifier)
      } else {
        throw BrowserRuntimeError.invalidState(
          "Profile identifier is missing for a permanent context")
      }
      let pendingProxy = webProxyEndpoints[contextID]
      await MainActor.run { if let pendingProxy { context.apply(proxy: pendingProxy) } }
      webContexts[contextID] = context
    }
    try await context.configure(rules: rules, enabled: enabled)
    if let snapshot = await context.rules { webContextRules[contextID] = snapshot }
    else { webContextRules[contextID] = nil }
    let applied = await context.rules
    for (id, page) in webPages where self.contextID(containing: id) == contextID {
      await page.applyRules(applied)
    }
  }

  public func setContextEphemeral(contextID: ContextID, enabled: Bool) async throws {
    _ = try requireContext(contextID)
    if enabled {
      webEphemeral.insert(contextID)
      if webContexts[contextID]?.isEphemeral != true { webContexts[contextID] = nil }
    } else {
      webEphemeral.remove(contextID)
      await purgeEphemeralStore(for: contextID)
      if webContexts[contextID]?.isEphemeral == true { webContexts[contextID] = nil }
    }
  }

  func purgeEphemeralStore(for contextID: ContextID) async {
    guard let store = webEphemeralStores.removeValue(forKey: contextID) as? WKWebsiteDataStore else { return }
    await MainActor.run {
      store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }
  }

  public func configureWebProxy(contextID: ContextID, endpoint: WebProxyEndpoint?) async throws {
    _ = try requireContext(contextID)
    if let endpoint { webProxyEndpoints[contextID] = endpoint }
    else { webProxyEndpoints.removeValue(forKey: contextID) }
    guard let context = webContexts[contextID] else { return }
    await MainActor.run { context.apply(proxy: endpoint) }
  }
}

extension WebKitContext {
  func apply(proxy endpoint: WebProxyEndpoint?) {
    guard let endpoint else {
      store.proxyConfigurations = []
      return
    }
    guard let port = NWEndpoint.Port(rawValue: endpoint.port) else {
      store.proxyConfigurations = []
      return
    }
    let nwEndpoint = NWEndpoint.hostPort(host: .name(endpoint.host, nil), port: port)
    var proxy = ProxyConfiguration(socksv5Proxy: nwEndpoint)
    proxy.allowFailover = !endpoint.failClosed
    if let username = endpoint.username, let password = endpoint.password {
      proxy.applyCredential(username: username, password: password)
    }
    store.proxyConfigurations = [proxy]
  }
}

extension WebKitContext {
  func configure(rules source: String, enabled: Bool) async throws {
    guard enabled else { rules = nil; return }
    let json = try AggressiveBlockFilter.compile(source: source)
    guard let data = json.data(using: .utf8),
      let decoded = try? JSONDecoder().decode([[String: [String: String]]].self, from: data),
      !decoded.isEmpty else { rules = nil; return }
    guard let store = WKContentRuleListStore.default() else {
      throw BrowserRuntimeError.invalidState("Content rule store is unavailable")
    }
    let identifier = "aether-\(String(format: "%016llx", WebKitContext.stableHash(json)))"
    if let cached: WKContentRuleList = try await withCheckedThrowingContinuation({ continuation in
      store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
        continuation.resume(returning: list)
      }
    }) {
      rules = cached
      return
    }
    rules = try await store.compileContentRuleList(
      forIdentifier: identifier, encodedContentRuleList: json)
  }

  static func stableHash(_ value: String) -> UInt64 {
    var hash: UInt64 = 14_695_901_793_932_658_723
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_096_221_680_031_431_921
    }
    return hash
  }
}

extension WebKitPage {
  func applyRules(_ rules: WKContentRuleList?) {
    view.configuration.userContentController.removeAllContentRuleLists()
    if let rules { view.configuration.userContentController.add(rules) }
  }
}

extension BrowserRuntime {
  /// Registers an already-constructed popup page so an agent can drive it.
  ///
  /// `createWebViewWith` must return synchronously on the main actor, so the `WebKitPage`
  /// and its document-start scripts are installed *there* — installing them after this hop
  /// is too late, because the popup has already begun loading, which leaves the page
  /// un-evaluable and its isolated-world DOM extractor absent. Only the `PageID` needs the
  /// actor, and that arrives here. The page is retained in `webPages`: WebKit does not
  /// strongly hold the view it was given, and dropping it mid-handshake kills the flow.
  func adoptPopup(_ popup: WebKitPage, opener: PageID) async {
    guard let openerContext = contextID(containing: opener) else {
      await popup.close()
      return
    }
    let info: BrowserPageInfo
    do {
      info = try await createPage(contextID: openerContext)
    } catch {
      await popup.close()
      return
    }
    webPages[info.id] = popup
    let sink: @Sendable (WebPageState) -> Void = { [weak self] state in
      Task { await self?.receiveWebState(state, pageID: info.id) }
    }
    await MainActor.run { popup.rebind(changed: sink) }
    await publishPageEvent(.popupOpened(url: popup.currentURL ?? ""), pageID: opener)
  }
}
