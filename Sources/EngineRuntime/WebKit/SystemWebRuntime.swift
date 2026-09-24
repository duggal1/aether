import AppKit
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
    if let pending = webPageTasks[id] { return await pending.value }
    let viewport = record.viewport
    let task = Task { @MainActor [weak self] in
      let page = WebKitPage(context: context, viewport: viewport) { [weak self] state in
        Task { await self?.receiveWebState(state, pageID: id) }
      }
      return page
    }
    webPageTasks[id] = task
    let page = await task.value
    WebKitNavigationProbe.log("webPage.ready id=\(id)")
    webPageTasks[id] = nil
    guard contextID(containing: id) != nil else {
      await page.close()
      throw BrowserRuntimeError.pageNotFound(id)
    }
    webPages[id] = page
    webContexts[record.contextID] = page.context
    return page
  }

  public func webSurface(pageID: PageID) async throws -> WKWebView {
    return try await webPage(pageID).view
  }

  public func isWebContentLive(pageID: PageID) -> Bool { webPages[pageID] != nil }

  public func warmProfileStore(contextID: ContextID) async throws {
    _ = try await webContextForCookies(contextID)
  }

  func restoreWebContent(_ id: PageID) async throws {
    guard webPages[id] == nil else { return }
    let record = try requirePage(id)
    let target = webStates[id]?.url
      ?? (record.history.indices.contains(record.historyIndex) ? record.history[record.historyIndex] : nil)
    _ = try await webPage(id)
    if let target { _ = try await navigateWeb(pageID: id, request: HTTPRequest(url: target)) }
  }

  func receiveWebState(_ state: WebPageState, pageID: PageID) {
    guard let contextID = contextID(containing: pageID),
      var page = contexts[contextID]?.pages[pageID],
      state.sequence > (webStates[pageID]?.sequence ?? 0) else { return }
    let previous = webStates[pageID]
    webStates[pageID] = state
    let historyChanged = !state.history.isEmpty
      && (page.history != state.history || page.historyIndex != state.historyIndex)
    let recordChanged = page.viewport != state.viewport || historyChanged
      || previous?.url != state.url || previous?.loading != state.loading
      || previous?.contentReady != state.contentReady || previous?.error != state.error
    guard recordChanged else {
      publishPageState(pageID)
      return
    }
    page.viewport = state.viewport
    page.lastActive = Date().timeIntervalSince1970
    if historyChanged {
      page.history = state.history
      page.historyIndex = state.historyIndex
    }
    updatePageRecord(page)
  }

  func synchronizedWebInfo(_ id: PageID) async throws -> BrowserPageInfo {
    let page = try await webPage(id)
    receiveWebState(await page.state(), pageID: id)
    return try pageInfo(id)
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
