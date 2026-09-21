import AppKit
import DOM
import EngineCore
import Foundation
import Networking
import WebKit

@MainActor
final class WebKitStoreCache {
  static let shared = WebKitStoreCache()
  private var named: [UUID: WKWebsiteDataStore] = [:]
  private let ephemeral = WKWebsiteDataStore.nonPersistent()

  func store(for identifier: UUID?) -> WKWebsiteDataStore {
    guard let identifier else { return ephemeral }
    if let existing = named[identifier] { return existing }
    let created = WKWebsiteDataStore(forIdentifier: identifier)
    named[identifier] = created
    return created
  }
}

extension BrowserRuntime {
  func webPage(_ id: PageID) async throws -> WebKitPage {
    let record = try requirePage(id)
    if let page = webPages[id] { return page }
    if let task = webPageTasks[id] { return await task.value }
    let identifier = webProfileIdentifiers[record.contextID]
    let context: WebKitContext
    if let existing = webContexts[record.contextID] { context = existing }
    else {
      let candidate = await WebKitContext(identifier: identifier)
      context = webContexts[record.contextID] ?? candidate
    }
    webContexts[record.contextID] = context
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
    webStates[pageID] = state
    page.viewport = state.viewport
    page.lastActive = Date().timeIntervalSince1970
    if !state.history.isEmpty {
      page.history = state.history
      page.historyIndex = state.historyIndex
    }
    contexts[contextID]?.pages[pageID] = page
  }

  func synchronizedWebInfo(_ id: PageID) async throws -> BrowserPageInfo {
    let page = try await webPage(id)
    receiveWebState(await page.state(), pageID: id)
    return try pageInfo(id)
  }

  func navigateWeb(pageID: PageID, request: HTTPRequest, settle: PageReadiness = .complete) async throws -> BrowserPageInfo {
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
    return try await synchronizedWebInfo(pageID)
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
    let context: WebKitContext
    if let existing = webContexts[contextID] { context = existing }
    else {
      context = await WebKitContext(identifier: webProfileIdentifiers[contextID])
      webContexts[contextID] = context
    }
    try await context.configure(rules: rules, enabled: enabled)
    for (id, page) in webPages where self.contextID(containing: id) == contextID {
      await page.applyRules(context.rules)
    }
  }
}

extension WebKitContext {
  func configure(rules source: String, enabled: Bool) async throws {
    guard enabled else { rules = nil; return }
    let domains = source.split(separator: "\n").filter { $0.hasPrefix("||") && $0.hasSuffix("^") }
      .map { String($0.dropFirst(2).dropLast()) }
    guard domains.count == source.split(separator: "\n").count else {
      throw BrowserRuntimeError.invalidState("WebKit content rules currently support domain blocking only")
    }
    guard !domains.isEmpty else { rules = nil; return }
    let content = domains.map { domain in
      ["trigger": ["url-filter": "^https?://([^/]+\\.)?" + NSRegularExpression.escapedPattern(for: domain) + "[/:]"],
       "action": ["type": "block"]]
    }
    let json = String(decoding: try JSONEncoder().encode(content), as: UTF8.self)
    rules = try await WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: "aether-" + UUID().uuidString, encodedContentRuleList: json)
  }
}

extension WebKitPage {
  func applyRules(_ rules: WKContentRuleList?) {
    view.configuration.userContentController.removeAllContentRuleLists()
    if let rules { view.configuration.userContentController.add(rules) }
  }
}
