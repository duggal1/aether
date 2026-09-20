import CSS
import Diagnostics
import Display
import DOM
import EngineCore
import Foundation
import Graphics
import HTML
import Images
import JavaScript
import Layout
import Navigation
import Networking
import Persistence
import Scheduler
import Storage
import Style
import WebAPI
import WebSecurity

public actor BrowserRuntime {
  private enum HistoryUpdate {
    case push
    case preserve
    case move(Int)
  }

  private struct PageRecord {
    var id: PageID
    var contextID: ContextID
    var viewport: Size
    var loaded: LoadedPage?
    var javascript: JSRuntime?
    var history: [URL]
    var historyIndex: Int
    var lifecycle: PageLifecycleState
    var scroll: Point
    var focused: NodeID?
    var hovered: NodeID?
    var lastActive: Double
    var lastHTML: String?
    var networkLog: [NetworkLogEntry]
    var dialogs: [DialogID: DialogRecord]
    var timers: JSTimerBridge?
    var liveViewport: LiveViewport?
    var styleBox: SharedStyledDocument?
    var pendingAction: PendingPageAction?
    var pipeline = FramePipelineState()
    var frames = FrameRecorder()
    var ledger = ResourceLedger()
  }

  private struct DialogRecord: Sendable {
    var id: DialogID
    var pageID: PageID
    var kind: String
    var message: String
    var defaultPrompt: String?
  }

  private struct SessionRecord: Sendable {
    var id: SessionID
    var name: String
    var contextIDs: [ContextID]
    var createdAt: Double
  }

  private struct DownloadRecord: Sendable {
    var id: DownloadID
    var contextID: ContextID
    var pageID: PageID?
    var url: URL
    var path: String?
    var state: String
    var bytes: Int
  }

  private struct ContextRecord {
    var id: ContextID
    var name: String
    var network: NetworkSession
    var storage: StoragePartition
    var permissions: PermissionStore
    var profile: ProfileStore?
    var pages: [PageID: PageRecord]
    var downloads: [DownloadID: DownloadRecord]
    var bookmarks: [BookmarkInfo]
  }

  private struct StoredSearchProvider: Codable {
    var endpoint: String
    var queryParameter: String
  }

  private let contextCounter = AtomicCounter()
  private let pageCounter = AtomicCounter()
  private let documentCounter = AtomicCounter()
  private let navigationCounter = AtomicCounter()
  private let requestCounter = AtomicCounter()
  private let dialogCounter = AtomicCounter()
  private let downloadCounter = AtomicCounter()
  private let sessionCounter = AtomicCounter()
  private let metricsCollector = MetricsCollector()
  private let scheduler = EngineScheduler()
  private var contexts: [ContextID: ContextRecord] = [:]
  private var sessions: [SessionID: SessionRecord] = [:]
  private var maxActivePages = 8
  private var fleetMemoryBudget = 512 * 1024 * 1024

  public init() {}

  public func createContext(name: String) -> BrowserContextInfo {
    let id = ContextID(rawValue: contextCounter.next())
    let record = ContextRecord(
      id: id,
      name: name.isEmpty ? "context-\(id.rawValue)" : name,
      network: NetworkSession(),
      storage: StoragePartition(contextID: id),
      permissions: PermissionStore(),
      profile: nil,
      pages: [:],
      downloads: [:],
      bookmarks: []
    )
    contexts[id] = record
    return BrowserContextInfo(id: id, name: record.name, pageCount: 0)
  }

  public func destroyContext(_ id: ContextID) throws {
    guard let removed = contexts.removeValue(forKey: id) else {
      throw BrowserRuntimeError.contextNotFound(id)
    }
    removed.profile?.close()
  }

  public func listContexts() -> [BrowserContextInfo] {
    contexts.values.sorted(by: { $0.id.rawValue < $1.id.rawValue }).map {
      BrowserContextInfo(id: $0.id, name: $0.name, pageCount: $0.pages.count)
    }
  }

  public func openProfile(contextID: ContextID, directory: URL) async throws {
    guard contexts[contextID] != nil else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    let profile = try ProfileStore.open(directory: directory)
    do {
      try await attachProfile(profile, contextID: contextID)
    } catch {
      profile.close()
      throw error
    }
  }

  private func attachProfile(_ profile: ProfileStore, contextID: ContextID) async throws {
    guard let context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    let name = context.name
    let cookies = try profile.loadCookies().map { row in
      Cookie(
        name: row.name, value: row.value, domain: row.domain, path: row.path,
        expires: row.expires, secure: row.secure, httpOnly: row.httpOnly,
        sameSite: row.sameSite, hostOnly: row.hostOnly)
    }
    context.network.restoreCookies(cookies)
    var snapshots: [CacheSnapshot] = []
    var stale: [String] = []
    for entry in try profile.loadCacheEntries() {
      guard let url = URL(string: entry.url),
        let headersData = entry.headersJSON.data(using: .utf8),
        let headers = try? JSONDecoder().decode([String: String].self, from: headersData),
        let body = profile.blobs.read(hash: entry.bodyHash)
      else {
        stale.append(entry.url)
        continue
      }
      snapshots.append(
        CacheSnapshot(
          response: HTTPResponse(
            requestID: RequestID(rawValue: 0), url: url, statusCode: entry.status,
            headers: headers, body: body),
          storedAt: entry.storedAt))
    }
    for url in stale { try? profile.deleteCacheEntry(url: url) }
    await context.network.restoreCache(snapshots)
    let stored = try profile.loadLocalStorage()
    var partitioned: [String: [String: String]] = [:]
    for row in stored { partitioned[row.origin, default: [:]][row.key] = row.value }
    context.storage.restoreAll(partitioned)
    var decisions: [Origin: [WebPermission: PermissionDecision]] = [:]
    for row in try profile.loadPermissions() {
      guard let url = URL(string: row.origin), let origin = Origin(url: url),
        let permission = WebPermission(rawValue: row.permission),
        let decision = PermissionDecision(rawValue: row.decision)
      else { continue }
      decisions[origin, default: [:]][permission] = decision
    }
    await context.permissions.restore(decisions)
    let bookmarks = try profile.loadBookmarks().map { row in
      BookmarkInfo(
        url: row.url, title: row.title, createdAt: row.createdAt.timeIntervalSince1970)
    }
    let sessionPages = try profile.loadSessionPages().filter { $0.context == name }
    let historyRows = try profile.loadHistory().filter { $0.context == name }
    guard var current = contexts[contextID] else {
      profile.close()
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    if let existing = current.profile { existing.close() }
    current.profile = profile
    current.bookmarks = bookmarks
    if current.pages.isEmpty {
      for slot in sessionPages.sorted(by: { $0.slot < $1.slot }) {
        let urls = historyRows.filter { $0.slot == slot.slot }.sorted(by: { $0.index < $1.index })
          .compactMap { URL(string: $0.url) }
        let id = PageID(rawValue: pageCounter.next())
        current.pages[id] = PageRecord(
          id: id, contextID: contextID,
          viewport: normalized(
            Size(width: slot.viewportWidth, height: slot.viewportHeight)),
          loaded: nil, javascript: nil, history: urls,
          historyIndex: urls.isEmpty ? -1 : min(max(0, slot.historyIndex), urls.count - 1),
          lifecycle: .discarded, scroll: Point(), focused: nil, hovered: nil,
          lastActive: nowSeconds(), lastHTML: nil, networkLog: [], dialogs: [:])
      }
    }
    try loadPersistedDownloads(into: &current)
    contexts[contextID] = current
  }

  public func checkpoint(contextID: ContextID) async throws {
    guard let context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    guard let profile = context.profile else {
      throw BrowserRuntimeError.profileNotConfigured(contextID)
    }
    let cookies = context.network.snapshotCookies().map { cookie in
      CookieRow(
        name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path,
        expires: cookie.expires, secure: cookie.secure, httpOnly: cookie.httpOnly,
        sameSite: cookie.sameSite, hostOnly: cookie.hostOnly)
    }
    try profile.saveCookies(cookies)
    var entries: [CacheEntry] = []
    var liveHashes = Set<String>()
    for snapshot in await context.network.snapshotCache() {
      let body = snapshot.response.body
      let hash = DiskCache.sha256Hex(body)
      if !profile.blobs.contains(hash) { try profile.blobs.write(hash: hash, data: body) }
      liveHashes.insert(hash)
      let headersData = (try? JSONEncoder().encode(snapshot.response.headers)) ?? Data()
      entries.append(
        CacheEntry(
          url: snapshot.response.url.absoluteString, status: snapshot.response.statusCode,
          headersJSON: String(data: headersData, encoding: .utf8) ?? "{}",
          etag: headerValue("etag", in: snapshot.response.headers),
          storedAt: snapshot.storedAt,
          maxAge: maxAgeSeconds(headers: snapshot.response.headers),
          bodyHash: hash, bodySize: body.count))
    }
    try profile.saveCacheEntries(entries)
    try profile.evictBlobs(keeping: liveHashes, maxBytes: profile.blobs.maxBytes)
    let stored = context.storage.snapshotAll().flatMap { origin, values in
      values.map { LocalStorageRow(origin: origin, key: $0.key, value: $0.value) }
    }
    try profile.saveLocalStorage(stored)
    let name = context.name
    let pages = context.pages.values.sorted { $0.id.rawValue < $1.id.rawValue }
    var historyRows: [HistoryRow] = []
    var sessionRows: [SessionPageRow] = []
    for (slot, page) in pages.enumerated() {
      sessionRows.append(
        SessionPageRow(
          context: name, slot: slot, historyIndex: page.historyIndex,
          viewportWidth: page.viewport.width, viewportHeight: page.viewport.height))
      for (index, url) in page.history.enumerated() {
        historyRows.append(
          HistoryRow(context: name, slot: slot, index: index, url: url.absoluteString))
      }
    }
    try profile.saveHistory(historyRows)
    try profile.saveSessionPages(sessionRows)
    let decisions = await context.permissions.snapshot()
    try profile.savePermissions(
      decisions.flatMap { origin, map in
        map.map {
          PermissionRow(
            origin: origin.description, permission: $0.key.rawValue,
            decision: $0.value.rawValue)
        }
      })
    try profile.saveBookmarks(
      context.bookmarks.map { bookmark in
        BookmarkRow(
          url: bookmark.url, title: bookmark.title,
          createdAt: Date(timeIntervalSince1970: bookmark.createdAt))
      })
    try persistDownloads(context)
  }

  public func profileUsage(contextID: ContextID) throws -> ProfileUsage {
    guard let context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    guard let profile = context.profile else {
      throw BrowserRuntimeError.profileNotConfigured(contextID)
    }
    return ProfileUsage(
      databaseBytes: profile.fileBytes(), blobBytes: profile.blobs.totalBytes())
  }

  public func setCheckpoint(contextID: ContextID, key: String, value: Data) throws {
    guard let profile = try requireContext(contextID).profile else {
      throw BrowserRuntimeError.profileNotConfigured(contextID)
    }
    try profile.setKV(scope: "checkpoints", key: key, value: value)
  }

  public func checkpointValue(contextID: ContextID, key: String) throws -> Data? {
    guard let profile = try requireContext(contextID).profile else {
      throw BrowserRuntimeError.profileNotConfigured(contextID)
    }
    return try profile.getKV(scope: "checkpoints", key: key)
  }

  public func addBookmark(contextID: ContextID, url: URL, title: String) throws -> BookmarkInfo {
    guard var context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    guard bookmarkable(url) else {
      throw BrowserRuntimeError.invalidNavigation("Bookmarks require an http(s) URL")
    }
    if let index = context.bookmarks.firstIndex(where: { $0.url == url.absoluteString }) {
      context.bookmarks[index].title = title
    } else {
      context.bookmarks.append(
        BookmarkInfo(url: url.absoluteString, title: title, createdAt: nowSeconds()))
    }
    contexts[contextID] = context
    guard let bookmark = context.bookmarks.first(where: { $0.url == url.absoluteString }) else {
      throw BrowserRuntimeError.invalidState("Bookmark was not stored")
    }
    return bookmark
  }

  public func listBookmarks(contextID: ContextID) throws -> [BookmarkInfo] {
    guard let context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    return context.bookmarks.sorted { $0.createdAt < $1.createdAt }
  }

  public func removeBookmark(contextID: ContextID, url: URL) throws -> Bool {
    guard var context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    guard
      let index = context.bookmarks.firstIndex(where: { $0.url == url.absoluteString })
    else { return false }
    context.bookmarks.remove(at: index)
    contexts[contextID] = context
    return true
  }

  public func suggestNavigation(
    contextID: ContextID, prefix: String, limit: Int = 8
  ) throws -> [NavigationSuggestion] {
    guard let context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    let needle = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !needle.isEmpty else {
      throw BrowserRuntimeError.invalidNavigation("A suggestion prefix is required")
    }
    guard limit >= 1 && limit <= 50 else {
      throw BrowserRuntimeError.invalidNavigation("Suggestion limit must be 1 through 50")
    }
    var suggestions: [NavigationSuggestion] = []
    var seen = Set<String>()
    for bookmark in context.bookmarks
      where bookmark.url.lowercased().contains(needle)
        || bookmark.title.lowercased().contains(needle)
    {
      suggestions.append(
        NavigationSuggestion(kind: "bookmark", url: bookmark.url, title: bookmark.title))
      seen.insert(bookmark.url)
      if suggestions.count >= limit { return suggestions }
    }
    let recent = context.pages.values.sorted { $0.lastActive > $1.lastActive }
    for page in recent {
      for url in page.history.reversed() {
        let absolute = url.absoluteString
        guard !seen.contains(absolute), absolute.lowercased().contains(needle) else { continue }
        seen.insert(absolute)
        suggestions.append(NavigationSuggestion(kind: "history", url: absolute))
        if suggestions.count >= limit { return suggestions }
      }
    }
    return suggestions
  }

  public func searchProvider(contextID: ContextID) throws -> SearchProvider {
    guard let context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    guard let profile = context.profile,
      let data = try profile.getKV(scope: "search", key: "provider"),
      let stored = try? JSONDecoder().decode(StoredSearchProvider.self, from: data),
      let endpoint = URL(string: stored.endpoint),
      let provider = try? SearchProvider.validated(
        endpoint: endpoint, queryParameter: stored.queryParameter)
    else { return .defaultProvider }
    return provider
  }

  public func setSearchProvider(
    contextID: ContextID, endpoint: URL, queryParameter: String = "q"
  ) throws -> SearchProvider {
    guard contexts[contextID] != nil else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    let provider = try SearchProvider.validated(
      endpoint: endpoint, queryParameter: queryParameter)
    guard let profile = try requireContext(contextID).profile else {
      throw BrowserRuntimeError.profileNotConfigured(contextID)
    }
    let stored = StoredSearchProvider(
      endpoint: endpoint.absoluteString, queryParameter: provider.queryParameter)
    try profile.setKV(scope: "search", key: "provider", value: try JSONEncoder().encode(stored))
    return provider
  }

  private func bookmarkable(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = url.host, !host.isEmpty
    else { return false }
    return true
  }

  public func createPage(contextID: ContextID, viewport: Size = Size(width: 1280, height: 800))
    throws -> BrowserPageInfo
  {
    guard var context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    let id = PageID(rawValue: pageCounter.next())
    let page = PageRecord(
      id: id,
      contextID: contextID,
      viewport: normalized(viewport),
      loaded: nil,
      javascript: nil,
      history: [],
      historyIndex: -1,
      lifecycle: .active,
      scroll: Point(),
      focused: nil,
      hovered: nil,
      lastActive: nowSeconds(),
      lastHTML: nil,
      networkLog: [],
      dialogs: [:]
    )
    context.pages[id] = page
    contexts[contextID] = context
    return info(for: page)
  }

  public func closePage(_ pageID: PageID) throws {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID] else {
      throw BrowserRuntimeError.pageNotFound(pageID)
    }
    context.pages.removeValue(forKey: pageID)
    contexts[contextID] = context
  }

  public func suspendPage(_ pageID: PageID) throws -> BrowserPageInfo {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID]
    else { throw BrowserRuntimeError.pageNotFound(pageID) }
    page.loaded = nil
    page.javascript = nil
    page.lifecycle = .discarded
    context.pages[pageID] = page
    contexts[contextID] = context
    return info(for: page)
  }

  public func listPages(contextID: ContextID) throws -> [BrowserPageInfo] {
    guard let context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    return context.pages.values.sorted(by: { $0.id.rawValue < $1.id.rawValue }).map(info(for:))
  }

  @discardableResult
  public func navigate(pageID: PageID, to url: URL) async throws -> BrowserPageInfo {
    try await performNavigation(pageID: pageID, request: HTTPRequest(url: url), history: .push)
  }

  @discardableResult
  public func navigate(pageID: PageID, request: HTTPRequest) async throws -> BrowserPageInfo {
    try await performNavigation(pageID: pageID, request: request, history: .push)
  }

  @discardableResult
  public func goBack(pageID: PageID) async throws -> BrowserPageInfo {
    let page = try requirePage(pageID)
    let targetIndex = page.historyIndex - 1
    guard page.history.indices.contains(targetIndex) else {
      throw BrowserRuntimeError.historyUnavailable
    }
    return try await performNavigation(
      pageID: pageID, request: HTTPRequest(url: page.history[targetIndex]),
      history: .move(targetIndex))
  }

  @discardableResult
  public func goForward(pageID: PageID) async throws -> BrowserPageInfo {
    let page = try requirePage(pageID)
    let targetIndex = page.historyIndex + 1
    guard page.history.indices.contains(targetIndex) else {
      throw BrowserRuntimeError.historyUnavailable
    }
    return try await performNavigation(
      pageID: pageID, request: HTTPRequest(url: page.history[targetIndex]),
      history: .move(targetIndex))
  }

  @discardableResult
  public func reload(pageID: PageID, bypassCache: Bool = false) async throws -> BrowserPageInfo {
    let page = try requirePage(pageID)
    guard let url = page.loaded?.url else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    var request = HTTPRequest(url: url)
    if bypassCache { request.cachePolicy = .reloadIgnoringCache }
    return try await performNavigation(pageID: pageID, request: request, history: .preserve)
  }

  public func inspect(pageID: PageID) throws -> PageInspection {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    let nodes = DOMSemantics.interactiveNodes(in: loaded.document).compactMap { semantic in
      makeInspectedNode(semantic.nodeID, loaded: loaded)
    }
    return PageInspection(page: info(for: page), nodes: nodes)
  }

  public func snapshot(pageID: PageID) throws -> PageSnapshot {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    let dom = loaded.document.snapshot()
    let nodes = dom.nodes.map { node -> PageNodeSnapshot in
      let source = loaded.document.node(node.id)
      let style = loaded.styledDocument.style(for: node.id)
      let role = source.flatMap(DOMSemantics.role(for:))
      return PageNodeSnapshot(
        id: node.id,
        parent: node.parent,
        children: node.children,
        kind: node.kind,
        tag: node.tag,
        text: node.text,
        attributes: node.attributes,
        role: role,
        name: node.name,
        visible: style.display != .none && source?.attribute("hidden") == nil,
        enabled: source?.attribute("disabled") == nil,
        editable: role == "textbox" || source?.attribute("contenteditable") == "true",
        bounds: loaded.layout.boxes[node.id]?.frame
      )
    }
    return PageSnapshot(
      page: info(for: page), documentID: dom.documentID, mutationVersion: dom.mutationVersion,
      nodes: nodes)
  }

  public func query(pageID: PageID, selector: String) throws -> InspectedNode? {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard let id = loaded.document.querySelector(selector) else { return nil }
    return makeInspectedNode(id, loaded: loaded)
  }

  public func queryAll(pageID: PageID, selector: String) throws -> [InspectedNode] {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    return loaded.document.querySelectorAll(selector).compactMap {
      makeInspectedNode($0, loaded: loaded)
    }
  }

  public func waitForSelector(
    pageID: PageID, selector: String, condition: SelectorWaitCondition = .visible,
    timeoutMilliseconds: UInt64 = 5_000, pollMilliseconds: UInt64 = 25
  ) async throws -> InspectedNode? {
    let clock = ContinuousClock()
    let started = clock.now
    while true {
      let node = try query(pageID: pageID, selector: selector)
      let satisfied: Bool
      switch condition {
      case .attached: satisfied = node != nil
      case .visible: satisfied = node?.visible == true
      case .hidden: satisfied = node != nil && node?.visible == false
      case .detached: satisfied = node == nil
      }
      if satisfied { return node }
      let elapsed = started.duration(to: clock.now)
      let elapsedMilliseconds =
        UInt64(max(0, elapsed.components.seconds * 1_000))
        + UInt64(max(0, elapsed.components.attoseconds / 1_000_000_000_000_000))
      if elapsedMilliseconds >= timeoutMilliseconds {
        throw BrowserRuntimeError.timeout(
          "Timed out waiting for selector \(selector) to become \(condition.rawValue)")
      }
      try await Task.sleep(for: .milliseconds(pollMilliseconds))
    }
  }

  @discardableResult
  public func click(pageID: PageID, nodeID: NodeID) async throws -> BrowserPageInfo {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard let node = loaded.document.node(nodeID) else {
      throw BrowserRuntimeError.nodeNotFound(nodeID)
    }
    guard node.attribute("disabled") == nil else { return info(for: page) }

    if let runtime = page.javascript {
      let before = loaded.document.mutationVersion
      do {
        let dispatch = try runtime.dispatchEvent(type: "click", target: nodeID)
        if loaded.document.mutationVersion != before { try refreshPage(pageID) }
        if dispatch.defaultPrevented { return info(for: try requirePage(pageID)) }
      } catch {
        throw BrowserRuntimeError.javascript(String(describing: error))
      }
    }

    if node.tagName == "input" {
      let type = node.attribute("type")?.lowercased() ?? "text"
      if type == "checkbox" {
        toggleCheckbox(nodeID, document: loaded.document)
        try dispatchMutationEvent("change", page: page, nodeID: nodeID, document: loaded.document)
        try refreshPage(pageID)
        return info(for: try requirePage(pageID))
      }
      if type == "radio" {
        toggleRadio(nodeID, document: loaded.document)
        try dispatchMutationEvent("change", page: page, nodeID: nodeID, document: loaded.document)
        try refreshPage(pageID)
        return info(for: try requirePage(pageID))
      }
    }

    if let anchor = ancestor(named: "a", from: nodeID, document: loaded.document),
      let href = loaded.document.node(anchor)?.attribute("href"),
      let target = URL(string: href, relativeTo: loaded.url)?.absoluteURL
    {
      return try await navigate(pageID: pageID, to: target)
    }

    if isSubmitControl(node),
      let form = ancestor(named: "form", from: nodeID, document: loaded.document)
    {
      let request = try formRequest(formID: form, activatedNodeID: nodeID, page: loaded)
      return try await performNavigation(pageID: pageID, request: request, history: .push)
    }

    return info(for: page)
  }

  public func type(pageID: PageID, nodeID: NodeID, text: String, append: Bool = false) throws {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard let node = loaded.document.node(nodeID) else {
      throw BrowserRuntimeError.nodeNotFound(nodeID)
    }
    let role = DOMSemantics.role(for: node)
    guard role == "textbox" || node.attribute("contenteditable") == "true" else {
      throw BrowserRuntimeError.nodeNotEditable(nodeID)
    }
    let existing = append ? currentValue(nodeID, document: loaded.document) : ""
    setControlValue(existing + text, nodeID: nodeID, document: loaded.document)
    try dispatchMutationEvent("input", page: page, nodeID: nodeID, document: loaded.document)
    try refreshPage(pageID)
  }

  public func setValue(pageID: PageID, nodeID: NodeID, value: String) throws {
    try type(pageID: pageID, nodeID: nodeID, text: value, append: false)
  }

  public func evaluate(pageID: PageID, source: String) throws -> JavaScriptResult {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID]
    else { throw BrowserRuntimeError.pageNotFound(pageID) }
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    let runtime: JSRuntime
    if let existing = page.javascript {
      runtime = existing
    } else {
      let storage = context.storage.localStorage(for: originKey(loaded.url))
      runtime = JSRuntime(document: loaded.document, localStorage: storage)
    }
    wireScriptRuntime(runtime, network: context.network)
    let before = loaded.document.mutationVersion
    do {
      let value = try runtime.evaluate(source)
      runtime.pumpTimers()
      page.javascript = runtime
      context.pages[pageID] = page
      contexts[contextID] = context
      if loaded.document.mutationVersion != before { try refreshPage(pageID) }
      return JavaScriptResult(value: value.description, console: runtime.consoleOutput)
    } catch {
      throw BrowserRuntimeError.javascript(String(describing: error))
    }
  }

  public func render(pageID: PageID, origin: Point = .zero) throws -> PixelBuffer {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID], var loaded = page.loaded
    else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    let (buffer, milliseconds) = try MetricClock.milliseconds {
      try SoftwareRenderer().render(loaded.displayList, viewport: page.viewport, origin: origin)
    }
    loaded.metrics.renderMilliseconds = milliseconds
    page.loaded = loaded
    context.pages[pageID] = page
    contexts[contextID] = context
    return buffer
  }

  public func metrics(pageID: PageID) throws -> EngineMetrics {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    return loaded.metrics
  }

  public func mutations(pageID: PageID, since version: UInt64) throws -> [DOMMutation] {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    return loaded.document.mutations(since: version)
  }

  public func captureState(pageID: PageID) throws -> CapturePageState {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    return CapturePageState(
      url: loaded.url, title: loaded.title, viewport: page.viewport,
      documentSize: loaded.layout.contentSize, scroll: page.scroll,
      statusCode: loaded.statusCode)
  }

  public func cachedResourceBytes(contextID: ContextID, url: URL, maximumBytes: Int)
    async throws -> Data?
  {
    guard let context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    guard let response = await context.network.cache.response(for: url) else { return nil }
    guard response.body.count <= max(0, maximumBytes) else { return nil }
    return response.body
  }

  public func captureDocument(
    pageID: PageID, includeComputedStyles: Bool, redactSensitive: Bool
  ) async throws -> CaptureDocumentData {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard let contextID = contextID(containing: pageID), let context = contexts[contextID] else {
      throw BrowserRuntimeError.pageNotFound(pageID)
    }
    let document = loaded.document
    var issues: [CaptureIssue] = []
    var stylesheets: [CapturedStylesheet] = []
    var resources: [CapturedResource] = []
    var seenResources = Set<String>()
    var redacted = false

    func addResource(_ url: URL, kind: String) {
      let key = url.absoluteString
      guard seenResources.insert(key).inserted else { return }
      resources.append(CapturedResource(url: key, kind: kind))
    }

    for id in document.depthFirst() {
      guard let node = document.node(id), let tag = node.tagName else { continue }
      switch tag {
      case "style":
        stylesheets.append(
          CapturedStylesheet(
            sourceURL: nil, media: node.attribute("media"),
            css: document.textContent(of: id)))
      case "link":
        let tokens =
          (node.attribute("rel") ?? "").lowercased().split(whereSeparator: { $0.isWhitespace })
          .map(String.init)
        guard let href = node.attribute("href"),
          let url = URL(string: href, relativeTo: loaded.url)?.absoluteURL
        else { continue }
        if tokens.contains("stylesheet") {
          if let response = await context.network.cache.response(for: url),
            let css = String(data: response.body, encoding: .utf8)
          {
            stylesheets.append(
              CapturedStylesheet(
                sourceURL: url.absoluteString, media: node.attribute("media"), css: css))
            addResource(url, kind: "css")
          } else {
            issues.append(
              CaptureIssue(code: "uncached-css", detail: url.absoluteString))
          }
        } else if tokens.contains("icon") {
          addResource(url, kind: "image")
        } else if tokens.contains("font") || tokens.contains("preload") {
          addResource(url, kind: "font")
        }
      case "img":
        if let src = node.attribute("src"),
          let url = URL(string: src, relativeTo: loaded.url)?.absoluteURL
        {
          addResource(url, kind: url.pathExtension.lowercased() == "svg" ? "svg" : "image")
        } else if node.attribute("src") != nil {
          issues.append(CaptureIssue(code: "unresolvable-url", detail: "img src is not a URL"))
        }
        for candidate in srcsetCandidates(node.attribute("srcset"), baseURL: loaded.url) {
          addResource(
            candidate, kind: candidate.pathExtension.lowercased() == "svg" ? "svg" : "image")
        }
      case "script":
        if let src = node.attribute("src"),
          let url = URL(string: src, relativeTo: loaded.url)?.absoluteURL
        {
          addResource(url, kind: "script")
        }
      case "source":
        if let src = node.attribute("src"),
          let url = URL(string: src, relativeTo: loaded.url)?.absoluteURL
        {
          addResource(url, kind: "media")
        }
        for candidate in srcsetCandidates(node.attribute("srcset"), baseURL: loaded.url) {
          addResource(candidate, kind: "media")
        }
      case "video", "audio":
        if let src = node.attribute("src"),
          let url = URL(string: src, relativeTo: loaded.url)?.absoluteURL
        {
          addResource(url, kind: "media")
        }
        if let poster = node.attribute("poster"),
          let url = URL(string: poster, relativeTo: loaded.url)?.absoluteURL
        {
          addResource(url, kind: "image")
        }
        issues.append(
          CaptureIssue(
            code: tag == "video" ? "video-content" : "audio-content",
            detail: "Media element pixels are captured in screenshots; markup is not replayable"))
      case "track":
        if let src = node.attribute("src"),
          let url = URL(string: src, relativeTo: loaded.url)?.absoluteURL
        {
          addResource(url, kind: "media")
        }
      case "input":
        if node.attribute("type")?.lowercased() == "image",
          let src = node.attribute("src"),
          let url = URL(string: src, relativeTo: loaded.url)?.absoluteURL
        {
          addResource(url, kind: "image")
        }
        if redactSensitive, node.attribute("type")?.lowercased() == "password" {
          redacted = true
        }
      case "canvas":
        issues.append(
          CaptureIssue(
            code: "canvas-content",
            detail: "Canvas pixels are captured in screenshots; drawing commands are not recoverable"
          ))
      case "iframe":
        issues.append(
          CaptureIssue(
            code: "frame-content",
            detail: "Cross-origin frame DOM is not accessible; pixels are captured when rendered"))
      case "object", "embed":
        issues.append(
          CaptureIssue(
            code: "embedded-content",
            detail: "<\(tag)> content is not recoverable as editable markup"))
      default:
        break
      }
      if redactSensitive, isRedactedNode(id, in: document) { redacted = true }
    }

    var sensitiveAncestors = Set<NodeID>()
    if redactSensitive {
      for id in document.depthFirst() where isRedactedNode(id, in: document) {
        var parent = document.node(id)?.parent
        while let ancestor = parent, sensitiveAncestors.insert(ancestor).inserted {
          parent = document.node(ancestor)?.parent
        }
      }
    }
    var nodes: [CapturedNode] = []
    for id in document.depthFirst() {
      guard let node = document.node(id), let tag = node.tagName,
        let box = loaded.layout.boxes[id], isCapturable(box.frame),
        loaded.styledDocument.style(for: id).display != .none
      else { continue }
      if nodes.count >= 20_000 {
        issues.append(
          CaptureIssue(
            code: "node-limit", detail: "Node list truncated at 20000 entries"))
        break
      }
      var text: String? = cappedText(document.textContent(of: id))
      if text?.isEmpty == true { text = nil }
      if redactSensitive,
        isRedactedNode(id, in: document) || sensitiveAncestors.contains(id)
      {
        text = nil
        redacted = true
      }
      nodes.append(
        CapturedNode(
          selector: selectorFor(id, in: document), tag: tag,
          role: DOMSemantics.role(for: node), text: text, bounds: box.frame,
          computedStyles: includeComputedStyles
            ? computedStyleMap(loaded.styledDocument.style(for: id)) : [:]))
    }
    if redacted {
      issues.append(
        CaptureIssue(code: "redaction-applied", detail: "Sensitive values were redacted"))
    }
    let html = HTMLSerialization.serialize(document, redactSensitive: redactSensitive)
    return CaptureDocumentData(
      html: html, stylesheets: stylesheets, nodes: nodes, resources: resources, issues: issues)
  }

  public func pageInfo(_ pageID: PageID) throws -> BrowserPageInfo {
    info(for: try requirePage(pageID))
  }

  public func resize(pageID: PageID, viewport: Size) throws -> BrowserPageInfo {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID]
    else { throw BrowserRuntimeError.pageNotFound(pageID) }
    page.viewport = normalized(viewport)
    context.pages[pageID] = page
    contexts[contextID] = context
    if page.loaded != nil { try refreshPage(pageID) }
    return info(for: try requirePage(pageID))
  }

  public func loadHTML(pageID: PageID, html: String, url: URL) async throws -> BrowserPageInfo {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID]
    else { throw BrowserRuntimeError.pageNotFound(pageID) }
    let (loaded, runtime) = buildLoaded(
      html: html, url: url, viewport: page.viewport, storage: context.storage,
      network: context.network, page: &page, jar: context.network.cookieJar)
    page.loaded = loaded
    page.javascript = runtime
    if page.historyIndex + 1 < page.history.count {
      page.history.removeSubrange((page.historyIndex + 1)..<page.history.count)
    }
    page.history.append(url)
    page.historyIndex = page.history.count - 1
    page.lifecycle = .active
    page.lastActive = nowSeconds()
    page.lastHTML = html
    page.scroll = Point()
    page.focused = nil
    page.hovered = nil
    page.networkLog.append(
      NetworkLogEntry(
        request: RequestID(rawValue: requestCounter.next()), navigation: loaded.navigationID,
        url: url.absoluteString, statusCode: loaded.statusCode,
        durationMilliseconds: loaded.metrics.totalMilliseconds, fromCache: false))
    page.networkLog = Array(page.networkLog.suffix(32))
    context.pages[pageID] = page
    contexts[contextID] = context
    return info(for: page)
  }

  public func lifecycleState(pageID: PageID) throws -> PageLifecycleState {
    try requirePage(pageID).lifecycle
  }

  public func setLifecycle(pageID: PageID, state: PageLifecycleState) async throws
    -> BrowserPageInfo
  {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID]
    else { throw BrowserRuntimeError.pageNotFound(pageID) }
    if page.loaded == nil && state != .discarded {
      contexts[contextID] = context
      try await restoreDiscarded(pageID: pageID)
      guard let refreshed = contexts[contextID]?.pages[pageID] else {
        throw BrowserRuntimeError.pageNotFound(pageID)
      }
      page = refreshed
      context = contexts[contextID] ?? context
    }
    switch state {
    case .active, .background:
      page.lifecycle = state
    case .suspended:
      page.javascript = nil
      page.lifecycle = .suspended
    case .frozen:
      page.javascript = nil
      if var loaded = page.loaded {
        loaded.images = [:]
        page.loaded = loaded
        context.pages[pageID] = page
        contexts[contextID] = context
        try refreshPage(pageID)
        guard let rebuilt = contexts[contextID]?.pages[pageID] else {
          throw BrowserRuntimeError.pageNotFound(pageID)
        }
        page = rebuilt
        context = contexts[contextID] ?? context
      }
      page.lifecycle = .frozen
    case .discarded:
      page.loaded = nil
      page.javascript = nil
      page.lifecycle = .discarded
    }
    page.lastActive = nowSeconds()
    context.pages[pageID] = page
    contexts[contextID] = context
    return info(for: page)
  }

  public func restorePage(pageID: PageID) async throws -> BrowserPageInfo {
    try await setLifecycle(pageID: pageID, state: .active)
  }

  public func fleetStats() -> FleetStats {
    var active = 0
    var background = 0
    var suspended = 0
    var frozen = 0
    var discarded = 0
    var bytes = 0
    var pages = 0
    for context in contexts.values {
      for page in context.pages.values {
        pages += 1
        bytes += estimatedBytes(of: page)
        switch page.lifecycle {
        case .active: active += 1
        case .background: background += 1
        case .suspended: suspended += 1
        case .frozen: frozen += 1
        case .discarded: discarded += 1
        }
      }
    }
    return FleetStats(
      totalContexts: contexts.count, totalPages: pages, active: active, background: background,
      suspended: suspended, frozen: frozen, discarded: discarded, estimatedBytes: bytes)
  }

  public func fleetPages() -> [FleetPageInfo] {
    contexts.values.flatMap { context in
      context.pages.values.map { page in
        FleetPageInfo(
          page: info(for: page), lifecycle: page.lifecycle, importance: importance(of: page),
          estimatedBytes: estimatedBytes(of: page))
      }
    }.sorted {
      if $0.page.contextID.rawValue != $1.page.contextID.rawValue {
        return $0.page.contextID.rawValue < $1.page.contextID.rawValue
      }
      return $0.page.id.rawValue < $1.page.id.rawValue
    }
  }

  public func sweepFleet(maxActive: Int? = nil, memoryBudgetBytes: Int? = nil) async throws -> [
    PageID: PageLifecycleState
  ] {
    if let maxActive { maxActivePages = max(1, maxActive) }
    if let memoryBudgetBytes { fleetMemoryBudget = max(1, memoryBudgetBytes) }
    let now = nowSeconds()
    var candidates: [FleetCandidate] = []
    for context in contexts.values {
      for page in context.pages.values {
        guard page.lifecycle == .active || page.lifecycle == .background else { continue }
        candidates.append(
          FleetCandidate(
            page: page.id.rawValue, importance: importance(of: page), lastActive: page.lastActive,
            estimatedBytes: estimatedBytes(of: page)))
      }
    }
    let plan = FleetScheduler.plan(
      candidates: candidates, maxActive: maxActivePages, memoryBudgetBytes: fleetMemoryBudget,
      now: now)
    var applied: [PageID: PageLifecycleState] = [:]
    for candidate in candidates {
      let pageID = PageID(rawValue: candidate.page)
      switch plan.action(for: candidate.page) {
      case .keep: continue
      case .suspend:
        _ = try await setLifecycle(pageID: pageID, state: .suspended)
        applied[pageID] = .suspended
      case .freeze:
        _ = try await setLifecycle(pageID: pageID, state: .frozen)
        applied[pageID] = .frozen
      case .discard:
        _ = try await setLifecycle(pageID: pageID, state: .discarded)
        applied[pageID] = .discarded
      }
    }
    return applied
  }

  public func hover(pageID: PageID, nodeID: NodeID) throws -> InspectedNode? {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard loaded.document.node(nodeID) != nil else {
      throw BrowserRuntimeError.nodeNotFound(nodeID)
    }
    storeHovered(nodeID, pageID: pageID)
    if let runtime = page.javascript {
      let before = loaded.document.mutationVersion
      try dispatchAll(["mouseover", "mouseenter", "mousemove"], runtime: runtime, target: nodeID)
      if loaded.document.mutationVersion != before { try refreshPage(pageID) }
    }
    return makeInspectedNode(nodeID, loaded: loaded)
  }

  public func focus(pageID: PageID, nodeID: NodeID) throws -> BrowserPageInfo {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard loaded.document.node(nodeID) != nil else {
      throw BrowserRuntimeError.nodeNotFound(nodeID)
    }
    if let previous = page.focused, previous != nodeID, let runtime = page.javascript {
      do { _ = try runtime.dispatchEvent(type: "blur", target: previous) } catch {
        throw BrowserRuntimeError.javascript(String(describing: error))
      }
    }
    storeFocused(nodeID, pageID: pageID)
    if let runtime = page.javascript {
      let before = loaded.document.mutationVersion
      try dispatchAll(["focus", "focusin"], runtime: runtime, target: nodeID)
      if loaded.document.mutationVersion != before { try refreshPage(pageID) }
    }
    return info(for: try requirePage(pageID))
  }

  public func blur(pageID: PageID) throws -> BrowserPageInfo {
    let page = try requirePage(pageID)
    guard page.loaded != nil else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    if let previous = page.focused, let runtime = page.javascript {
      do { _ = try runtime.dispatchEvent(type: "blur", target: previous) } catch {
        throw BrowserRuntimeError.javascript(String(describing: error))
      }
    }
    storeFocused(nil, pageID: pageID)
    return info(for: try requirePage(pageID))
  }

  public func focusedNode(pageID: PageID) throws -> InspectedNode? {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard let focused = page.focused else { return nil }
    return makeInspectedNode(focused, loaded: loaded)
  }

  public func hoveredNode(pageID: PageID) throws -> InspectedNode? {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard let hovered = page.hovered else { return nil }
    return makeInspectedNode(hovered, loaded: loaded)
  }

  public func scrollTo(pageID: PageID, x: Double, y: Double) throws -> Point {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID]
    else { throw BrowserRuntimeError.pageNotFound(pageID) }
    guard page.loaded != nil else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    page.scroll = Point(x: max(0, x), y: max(0, y))
    page.lastActive = nowSeconds()
    context.pages[pageID] = page
    contexts[contextID] = context
    return page.scroll
  }

  public func scrollOffset(pageID: PageID) throws -> Point {
    let page = try requirePage(pageID)
    guard page.loaded != nil else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    return page.scroll
  }

  public func scrollIntoView(pageID: PageID, nodeID: NodeID) throws -> Point {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard let box = loaded.layout.boxes[nodeID] else {
      throw BrowserRuntimeError.nodeNotFound(nodeID)
    }
    return try scrollTo(pageID: pageID, x: max(0, box.frame.minX), y: max(0, box.frame.minY))
  }

  public func nodeAtPoint(pageID: PageID, x: Double, y: Double) throws -> InspectedNode? {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    let target = Point(x: x + page.scroll.x, y: y + page.scroll.y)
    guard let id = HitTesting.node(at: target, in: loaded.layout) else { return nil }
    return makeInspectedNode(id, loaded: loaded)
  }

  public func pressKey(pageID: PageID, key: String) async throws -> String {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard let focused = page.focused,
      let node = loaded.document.node(focused)
    else {
      throw BrowserRuntimeError.invalidState("No focused node for keyboard input")
    }
    let role = DOMSemantics.role(for: node)
    switch key {
    case "Escape":
      _ = try blur(pageID: pageID)
      return ""
    case "Tab":
      advanceFocus(pageID: pageID)
      return ""
    default: break
    }
    guard role == "textbox" || node.attribute("contenteditable") == "true" else {
      throw BrowserRuntimeError.nodeNotEditable(focused)
    }
    if key == "Enter", node.tagName != "textarea",
      node.attribute("contenteditable") == nil,
      let form = ancestor(named: "form", from: focused, document: loaded.document)
    {
      if let runtime = page.javascript {
        try dispatchAll(["keydown", "keypress", "keyup"], runtime: runtime, target: focused)
      }
      let request = try formRequest(formID: form, activatedNodeID: focused, page: loaded)
      _ = try await performNavigation(pageID: pageID, request: request, history: .push)
      return ""
    }
    let current = currentValue(focused, document: loaded.document)
    let updated: String
    if key == "Backspace" || key == "Delete" {
      updated = current.isEmpty ? current : String(current.dropLast())
    } else if key == "Enter" {
      guard node.tagName == "textarea" || node.attribute("contenteditable") != nil else {
        throw BrowserRuntimeError.invalidState("Unsupported key: Enter")
      }
      updated = current + "\n"
    } else if key.count == 1 {
      updated = current + key
    } else {
      throw BrowserRuntimeError.invalidState("Unsupported key: \(key)")
    }
    if let runtime = page.javascript {
      try dispatchAll(["keydown", "keypress", "keyup"], runtime: runtime, target: focused)
    }
    setControlValue(updated, nodeID: focused, document: loaded.document)
    try dispatchMutationEvent("input", page: page, nodeID: focused, document: loaded.document)
    try refreshPage(pageID)
    return updated
  }

  public func selectOption(pageID: PageID, selectNodeID: NodeID, value: String) throws {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard let select = loaded.document.node(selectNodeID), select.tagName == "select" else {
      throw BrowserRuntimeError.invalidState("Node is not a select element")
    }
    let options = loaded.document.depthFirst(from: selectNodeID).filter {
      loaded.document.node($0)?.tagName == "option"
    }
    let matches = options.filter {
      guard let option = loaded.document.node($0) else { return false }
      return (option.attribute("value") ?? loaded.document.textContent(of: $0)) == value
    }
    guard !matches.isEmpty else {
      throw BrowserRuntimeError.invalidState("No option with value: \(value)")
    }
    if select.attribute("multiple") == nil {
      for option in options { loaded.document.removeAttribute("selected", from: option) }
      loaded.document.setAttribute("selected", value: "", on: matches[0])
    } else {
      for match in matches { loaded.document.setAttribute("selected", value: "", on: match) }
    }
    try dispatchMutationEvent("input", page: page, nodeID: selectNodeID, document: loaded.document)
    try dispatchMutationEvent("change", page: page, nodeID: selectNodeID, document: loaded.document)
    try refreshPage(pageID)
  }

  public func fill(pageID: PageID, nodeID: NodeID, value: String) throws {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard let node = loaded.document.node(nodeID) else {
      throw BrowserRuntimeError.nodeNotFound(nodeID)
    }
    let role = DOMSemantics.role(for: node)
    guard role == "textbox" || node.attribute("contenteditable") == "true" else {
      throw BrowserRuntimeError.nodeNotEditable(nodeID)
    }
    setControlValue(value, nodeID: nodeID, document: loaded.document)
    try dispatchMutationEvent("input", page: page, nodeID: nodeID, document: loaded.document)
    try dispatchMutationEvent("change", page: page, nodeID: nodeID, document: loaded.document)
    try refreshPage(pageID)
  }

  public func submitForm(pageID: PageID, formNodeID: NodeID) async throws -> BrowserPageInfo {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard let form = loaded.document.node(formNodeID), form.tagName == "form" else {
      throw BrowserRuntimeError.invalidForm("Node is not a form element")
    }
    let request = try formRequest(formID: formNodeID, activatedNodeID: formNodeID, page: loaded)
    return try await performNavigation(pageID: pageID, request: request, history: .push)
  }

  public func historyEntries(pageID: PageID) throws -> [HistoryEntry] {
    let page = try requirePage(pageID)
    return page.history.enumerated().map { index, url in
      HistoryEntry(index: index, url: url.absoluteString, current: index == page.historyIndex)
    }
  }

  public func consoleOutput(pageID: PageID) throws -> [String] {
    let page = try requirePage(pageID)
    guard page.loaded != nil else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    return page.javascript?.consoleOutput ?? []
  }

  public func networkLogEntries(pageID: PageID) throws -> [NetworkLogEntry] {
    try requirePage(pageID).networkLog
  }

  public func mainFrame(pageID: PageID) throws -> AgentFrameInfo {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    return AgentFrameInfo(
      id: FrameID(rawValue: loaded.document.id.rawValue), page: pageID, url: loaded.url.absoluteString,
      title: loaded.title)
  }

  public func listWorkers(pageID: PageID) throws -> [WorkerID] {
    _ = try requirePage(pageID)
    return []
  }

  public func listCookies(contextID: ContextID) async throws -> [CookieInfo] {
    let context = try requireContext(contextID)
    return context.network.snapshotCookies().map(cookieInfo).sorted {
      if $0.domain != $1.domain { return $0.domain < $1.domain }
      return $0.name < $1.name
    }
  }

  public func setCookie(contextID: ContextID, cookie: CookieInfo) async throws {
    let context = try requireContext(contextID)
    context.network.cookieJar.store(
      Cookie(
        name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path,
        secure: cookie.secure, httpOnly: cookie.httpOnly, sameSite: cookie.sameSite))
  }

  public func removeCookie(contextID: ContextID, name: String, domain: String, path: String = "/")
    async throws
  {
    let context = try requireContext(contextID)
    context.network.cookieJar.remove(name: name, domain: domain, path: path)
  }

  public func clearCookies(contextID: ContextID) async throws {
    let context = try requireContext(contextID)
    context.network.cookieJar.clear()
  }

  public func storageOrigins(contextID: ContextID) throws -> [String] {
    try requireContext(contextID).storage.origins()
  }

  public func storageValues(contextID: ContextID, origin: String) throws -> [String: String] {
    try requireContext(contextID).storage.localStorage(for: origin).snapshot()
  }

  public func storageSet(contextID: ContextID, origin: String, key: String, value: String) throws {
    try requireContext(contextID).storage.localStorage(for: origin).set(key, value: value)
  }

  public func storageRemove(contextID: ContextID, origin: String, key: String) throws {
    try requireContext(contextID).storage.localStorage(for: origin).remove(key)
  }

  public func storageClear(contextID: ContextID, origin: String) throws {
    try requireContext(contextID).storage.clear(origin: origin)
  }

  public func permissionDecision(contextID: ContextID, permission: String, origin: String) async throws
    -> String
  {
    let context = try requireContext(contextID)
    guard let parsed = WebPermission(rawValue: permission) else {
      throw BrowserRuntimeError.invalidState("Unknown permission: \(permission)")
    }
    guard let url = URL(string: origin), let parsedOrigin = Origin(url: url) else {
      throw BrowserRuntimeError.invalidState("Invalid origin: \(origin)")
    }
    return await context.permissions.effectiveDecision(
      for: parsed, origin: parsedOrigin, isTopLevel: true
    ).rawValue
  }

  public func setPermission(
    contextID: ContextID, permission: String, origin: String, decision: String
  ) async throws {
    let context = try requireContext(contextID)
    guard let parsed = WebPermission(rawValue: permission) else {
      throw BrowserRuntimeError.invalidState("Unknown permission: \(permission)")
    }
    guard let parsedDecision = PermissionDecision(rawValue: decision) else {
      throw BrowserRuntimeError.invalidState("Unknown decision: \(decision)")
    }
    guard let url = URL(string: origin), let parsedOrigin = Origin(url: url) else {
      throw BrowserRuntimeError.invalidState("Invalid origin: \(origin)")
    }
    await context.permissions.set(parsedDecision, for: parsed, origin: parsedOrigin)
  }

  public func listPermissions(contextID: ContextID) async throws -> [PermissionInfo] {
    let context = try requireContext(contextID)
    return await context.permissions.snapshot().flatMap { origin, map in
      map.map {
        PermissionInfo(
          origin: origin.description, permission: $0.key.rawValue, decision: $0.value.rawValue)
      }
    }.sorted {
      if $0.origin != $1.origin { return $0.origin < $1.origin }
      return $0.permission < $1.permission
    }
  }

  public func pendingDialogs(pageID: PageID) throws -> [AgentDialogInfo] {
    let page = try requirePage(pageID)
    return page.dialogs.values.sorted { $0.id.rawValue < $1.id.rawValue }.map { record in
      AgentDialogInfo(
        id: record.id, page: record.pageID, kind: record.kind, message: record.message,
        defaultPrompt: record.defaultPrompt)
    }
  }

  public func resolveDialog(id: DialogID, accept: Bool, promptText: String? = nil) throws -> Bool {
    for (contextID, var context) in contexts {
      for (pageID, var page) in context.pages {
        guard page.dialogs[id] != nil else { continue }
        page.dialogs.removeValue(forKey: id)
        context.pages[pageID] = page
        contexts[contextID] = context
        return accept
      }
    }
    throw BrowserRuntimeError.dialogNotFound(id)
  }

  public func startDownload(contextID: ContextID, url: String, path: String?) async throws
    -> AgentDownloadInfo
  {
    guard var context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    guard let target = URL(string: url) else {
      throw BrowserRuntimeError.downloadBlocked("Download URL is invalid")
    }
    switch DownloadPolicy.decide(url: target, from: nil) {
    case .deny(let reason): throw BrowserRuntimeError.downloadBlocked(reason)
    case .allow: break
    }
    let id = DownloadID(rawValue: downloadCounter.next())
    let record: DownloadRecord
    do {
      let response = try await context.network.fetch(target)
      let output =
        (path?.isEmpty == false ? path! : temporaryDownloadPath(id: id))
      let outputURL = URL(fileURLWithPath: output)
      if let parent = outputURL.deletingLastPathComponent().path as String? {
        try FileManager.default.createDirectory(
          atPath: parent, withIntermediateDirectories: true, attributes: nil)
      }
      try response.body.write(to: outputURL, options: .atomic)
      record = DownloadRecord(
        id: id, contextID: contextID, pageID: nil, url: target, path: output, state: "completed",
        bytes: response.body.count)
    } catch {
      record = DownloadRecord(
        id: id, contextID: contextID, pageID: nil, url: target, path: nil, state: "failed", bytes: 0)
      context.downloads[id] = record
      contexts[contextID] = context
      try persistDownloads(context)
      throw BrowserRuntimeError.invalidNavigation(String(describing: error))
    }
    context.downloads[id] = record
    contexts[contextID] = context
    try persistDownloads(context)
    return downloadInfo(record)
  }

  public func listDownloads(contextID: ContextID) throws -> [AgentDownloadInfo] {
    let context = try requireContext(contextID)
    return context.downloads.values.sorted { $0.id.rawValue < $1.id.rawValue }.map(downloadInfo)
  }

  public func clearDownloads(contextID: ContextID) throws {
    guard var context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    context.downloads.removeAll(keepingCapacity: false)
    contexts[contextID] = context
    try persistDownloads(context)
  }

  public func createSession(name: String) -> BrowserSessionInfo {
    let id = SessionID(rawValue: sessionCounter.next())
    let record = SessionRecord(
      id: id, name: name.isEmpty ? "session-\(id.rawValue)" : name,
      contextIDs: contexts.values.sorted { $0.id.rawValue < $1.id.rawValue }.map(\.id),
      createdAt: nowSeconds())
    sessions[id] = record
    return BrowserSessionInfo(
      id: id, name: record.name, contextCount: record.contextIDs.count,
      createdAt: record.createdAt)
  }

  public func listSessions() -> [BrowserSessionInfo] {
    sessions.values.sorted { $0.id.rawValue < $1.id.rawValue }.map { record in
      BrowserSessionInfo(
        id: record.id, name: record.name, contextCount: record.contextIDs.count,
        createdAt: record.createdAt)
    }
  }

  public func deleteSession(_ id: SessionID) throws {
    guard sessions.removeValue(forKey: id) != nil else {
      throw BrowserRuntimeError.sessionNotFound(id)
    }
  }

  public func sessionPages(_ id: SessionID) throws -> [FleetPageInfo] {
    guard let session = sessions[id] else { throw BrowserRuntimeError.sessionNotFound(id) }
    var result: [FleetPageInfo] = []
    for contextID in session.contextIDs {
      guard let context = contexts[contextID] else { continue }
      for page in context.pages.values {
        result.append(
          FleetPageInfo(
            page: info(for: page), lifecycle: page.lifecycle, importance: importance(of: page),
            estimatedBytes: estimatedBytes(of: page)))
      }
    }
    return result.sorted { $0.page.id.rawValue < $1.page.id.rawValue }
  }

  private func wireScriptRuntime(_ runtime: JSRuntime, network: NetworkSession) {
    if runtime.timerHost == nil {
      runtime.timerHost = JSTimerBridge(runtime: runtime)
    }
    if runtime.asyncFetch == nil {
      FetchBridge(network: network).install(into: runtime)
    }
  }

  private func performNavigation(pageID: PageID, request: HTTPRequest, history: HistoryUpdate)
    async throws -> BrowserPageInfo
  {
    guard let contextID = contextID(containing: pageID), let initialContext = contexts[contextID],
      let initialPage = initialContext.pages[pageID]
    else { throw BrowserRuntimeError.pageNotFound(pageID) }
    let pipeline = NavigationPipeline(
      network: initialContext.network, metricsCollector: metricsCollector)
    var loaded: LoadedPage
    do {
      loaded = try await pipeline.load(request, viewport: initialPage.viewport)
    } catch {
      throw BrowserRuntimeError.invalidNavigation(String(describing: error))
    }
    let storage = initialContext.storage.localStorage(for: originKey(loaded.url))
    let mutationVersion = loaded.document.mutationVersion
    let host = PageScriptHost(
      document: loaded.document, localStorage: storage, network: initialContext.network)
    guard var context = contexts[contextID], var page = context.pages[pageID] else {
      throw BrowserRuntimeError.pageNotFound(pageID)
    }
    configureRuntime(
      host.runtime, page: &page, loaded: loaded, jar: context.network.cookieJar,
      network: context.network)
    loaded.scriptErrors.append(contentsOf: host.run(loaded.scripts))
    host.pump()
    let runtime = host.runtime
    if loaded.document.mutationVersion != mutationVersion {
      loaded = pipeline.relayout(loaded, viewport: initialPage.viewport)
    }
    page.styleBox?.styled = loaded.styledDocument
    page.loaded = loaded
    page.javascript = runtime
    page.lifecycle = .active
    page.lastActive = nowSeconds()
    page.lastHTML = nil
    page.networkLog.append(
      NetworkLogEntry(
        request: loggedRequestID(for: request), navigation: loaded.navigationID,
        url: loaded.url.absoluteString, statusCode: loaded.statusCode,
        durationMilliseconds: loaded.metrics.totalMilliseconds, fromCache: false))
    page.networkLog = Array(page.networkLog.suffix(32))
    switch history {
    case .push:
      if page.historyIndex + 1 < page.history.count {
        page.history.removeSubrange((page.historyIndex + 1)..<page.history.count)
      }
      page.history.append(loaded.url)
      page.historyIndex = page.history.count - 1
    case .preserve:
      if page.history.indices.contains(page.historyIndex) {
        page.history[page.historyIndex] = loaded.url
      } else {
        page.history = [loaded.url]
        page.historyIndex = 0
      }
    case .move(let index):
      guard page.history.indices.contains(index) else {
        throw BrowserRuntimeError.historyUnavailable
      }
      page.history[index] = loaded.url
      page.historyIndex = index
    }
    context.pages[pageID] = page
    contexts[contextID] = context
    return info(for: page)
  }

  private func nowSeconds() -> Double { Date().timeIntervalSince1970 }

  private func estimatedBytes(of page: PageRecord) -> Int {
    guard let loaded = page.loaded else { return 0 }
    let imageBytes = loaded.images.values.reduce(0) { $0 + $1.rgba.count }
    return loaded.document.nodeCount * 256 + loaded.displayList.commands.count * 128 + imageBytes
      + loaded.metrics.responseBytes
  }

  private func importance(of page: PageRecord) -> Double {
    var score = page.loaded == nil ? 0.0 : 50.0
    if page.lifecycle == .active { score += 25 }
    if page.javascript != nil { score += 10 }
    return score
  }

  private func loggedRequestID(for request: HTTPRequest) -> RequestID {
    request.id.rawValue == 0 ? RequestID(rawValue: requestCounter.next()) : request.id
  }

  private func cookieInfo(_ cookie: Cookie) -> CookieInfo {
    CookieInfo(
      name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path,
      secure: cookie.secure, httpOnly: cookie.httpOnly, sameSite: cookie.sameSite)
  }

  private func downloadInfo(_ record: DownloadRecord) -> AgentDownloadInfo {
    AgentDownloadInfo(
      id: record.id, page: record.pageID, url: record.url.absoluteString, path: record.path,
      state: record.state, bytes: record.bytes)
  }

  private func temporaryDownloadPath(id: DownloadID) -> String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("aether-download-\(id.rawValue)").path
  }

  private func storeFocused(_ id: NodeID?, pageID: PageID) {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID]
    else { return }
    page.focused = id
    page.lastActive = nowSeconds()
    context.pages[pageID] = page
    contexts[contextID] = context
  }

  private func storeHovered(_ id: NodeID, pageID: PageID) {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID]
    else { return }
    page.hovered = id
    page.lastActive = nowSeconds()
    context.pages[pageID] = page
    contexts[contextID] = context
  }

  private func advanceFocus(pageID: PageID) {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID], let loaded = page.loaded
    else { return }
    let candidates = DOMSemantics.interactiveNodes(in: loaded.document).filter(\.editable)
      .map(\.nodeID)
    guard !candidates.isEmpty else { return }
    if let focused = page.focused, let index = candidates.firstIndex(of: focused) {
      page.focused = candidates[(index + 1) % candidates.count]
    } else {
      page.focused = candidates[0]
    }
    page.lastActive = nowSeconds()
    context.pages[pageID] = page
    contexts[contextID] = context
  }

  private func dispatchAll(_ types: [String], runtime: JSRuntime, target: NodeID) throws {
    do {
      for type in types { _ = try runtime.dispatchEvent(type: type, target: target) }
    } catch {
      throw BrowserRuntimeError.javascript(String(describing: error))
    }
  }

  private func persistDownloads(_ context: ContextRecord) throws {
    guard let profile = context.profile else { return }
    let records = context.downloads.values.sorted { $0.id.rawValue < $1.id.rawValue }.map {
      PersistedDownload(
        id: $0.id.rawValue, url: $0.url.absoluteString, path: $0.path, state: $0.state,
        bytes: $0.bytes)
    }
    try profile.setKV(
      scope: "downloads", key: "all", value: try JSONEncoder().encode(records))
  }

  private func loadPersistedDownloads(into context: inout ContextRecord) throws {
    guard let profile = context.profile,
      let data = try profile.getKV(scope: "downloads", key: "all"),
      let records = try? JSONDecoder().decode([PersistedDownload].self, from: data)
    else { return }
    for record in records {
      guard let url = URL(string: record.url) else { continue }
      let id = DownloadID(rawValue: downloadCounter.next())
      context.downloads[id] = DownloadRecord(
        id: id, contextID: context.id, pageID: nil, url: url, path: record.path,
        state: record.state, bytes: record.bytes)
    }
  }

  private func configureRuntime(
    _ runtime: JSRuntime, page: inout PageRecord, loaded: LoadedPage, jar: CookieJar,
    network: NetworkSession
  ) {
    let timers = JSTimerBridge(runtime: runtime)
    runtime.timerHost = timers
    page.timers = timers

    let viewportBox = page.liveViewport ?? LiveViewport(page.viewport)
    viewportBox.size = page.viewport
    page.liveViewport = viewportBox

    let styleBox = page.styleBox ?? SharedStyledDocument()
    styleBox.styled = loaded.styledDocument
    page.styleBox = styleBox

    let pending = page.pendingAction ?? PendingPageAction()
    page.pendingAction = pending

    let pageURL = loaded.url
    let pageOrigin = Origin(url: pageURL) ?? .opaque
    runtime.hostHooks.cookieString = { jar.scriptVisibleHeader(for: pageURL) ?? "" }
    runtime.hostHooks.setCookieString = { jar.absorb(setCookie: $0, from: pageURL) }
    runtime.hostHooks.viewportSize = { [viewportBox] in
      let size = viewportBox.size
      return (size.width, size.height)
    }
    runtime.hostHooks.currentURL = { pageURL.absoluteString }
    runtime.hostHooks.userAgent = { PageHostWiring.userAgent }
    runtime.hostHooks.mediaQueryHandler = { [viewportBox] query in
      MediaQuery.matchesAny(query, viewport: viewportBox.size)
    }
    runtime.hostHooks.computedStyleHandler = { [styleBox] id, name in
      guard let styled = styleBox.styled else { return nil }
      return PageHostWiring.computedStyleValue(styled.style(for: id), property: name)
    }
    runtime.hostHooks.navigate = { [pending] urlString in
      guard let url = URL(string: urlString, relativeTo: pageURL)?.absoluteURL else { return }
      pending.requestNavigation(url)
    }
    runtime.hostHooks.formSubmitHandler = { [pending] formID in
      pending.requestSubmit(formID)
    }
    runtime.asyncFetch = PageHostWiring.fetchHandler(
      network: network, pageURL: pageURL, pageOrigin: pageOrigin)
  }

  private func settlePageActions(pageID: PageID) async throws {
    guard let contextID = contextID(containing: pageID),
      let page = contexts[contextID]?.pages[pageID],
      let loaded = page.loaded, let runtime = page.javascript,
      let pending = page.pendingAction
    else { return }
    _ = runtime.pumpTimers()
    let actions = pending.take()
    if let form = actions.submit, loaded.document.node(form)?.tagName == "form" {
      do {
        _ = try await submitForm(pageID: pageID, formNodeID: form)
      } catch {
        appendScriptError(pageID: pageID, message: String(describing: error))
      }
      return
    }
    if let url = actions.navigation {
      _ = try await performNavigation(
        pageID: pageID, request: HTTPRequest(url: url), history: .push)
    }
  }

  private func appendScriptError(pageID: PageID, message: String) {
    guard let contextID = contextID(containing: pageID),
      var page = contexts[contextID]?.pages[pageID], var loaded = page.loaded,
      var context = contexts[contextID]
    else { return }
    loaded.scriptErrors.append(message)
    page.loaded = loaded
    context.pages[pageID] = page
    contexts[contextID] = context
  }

  private func buildLoaded(
    html: String, url: URL, viewport: Size, storage: StoragePartition, network: NetworkSession,
    page: inout PageRecord, jar: CookieJar
  ) -> (LoadedPage, JSRuntime) {
    let totalClock = ContinuousClock()
    let totalStart = totalClock.now
    let navigationID = NavigationID(rawValue: navigationCounter.next())
    let (parseResult, parseMilliseconds) = MetricClock.milliseconds {
      HTMLParser.parse(html, documentID: DocumentID(rawValue: documentCounter.next()))
    }
    let document = parseResult.document
    let resources = ResourceDiscovery.discover(in: document, baseURL: url)
    var sheets: [Stylesheet] = []
    var order = 0
    for inline in resources.inlineStyles {
      let sheet = CSSParser.parse(inline, startingSourceOrder: order)
      order += sheet.rules.count
      sheets.append(sheet)
    }
    var scripts: [String] = []
    var scriptErrors: [String] = []
    for script in resources.scripts {
      switch script {
      case .inline(let source):
        if !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          scripts.append(source)
        }
      case .external(let external):
        scriptErrors.append("External script skipped in loadHTML: \(external.absoluteString)")
      }
    }
    let imageErrors = resources.images.map {
      "External image skipped in loadHTML: \($0.url.absoluteString)"
    }
    let (styled, styleMilliseconds) = MetricClock.milliseconds {
      StyleResolver.resolve(document: document, stylesheets: sheets, viewport: viewport)
    }
    let (layout, layoutMilliseconds) = MetricClock.milliseconds {
      LayoutEngine().layout(styled, viewport: viewport)
    }
    let (displayList, displayListMilliseconds) = MetricClock.milliseconds {
      DisplayListBuilder.build(document: document, layout: layout)
    }
    let totalDuration = totalStart.duration(to: totalClock.now)
    let totalMilliseconds =
      Double(totalDuration.components.seconds) * 1000 + Double(totalDuration.components.attoseconds)
      / 1e15
    var loaded = LoadedPage(
      navigationID: navigationID, url: url, statusCode: 200, title: document.documentTitle(),
      document: document, styledDocument: styled, layout: layout, displayList: displayList,
      metrics: EngineMetrics(
        parseMilliseconds: parseMilliseconds, styleMilliseconds: styleMilliseconds,
        layoutMilliseconds: layoutMilliseconds, displayListMilliseconds: displayListMilliseconds,
        totalMilliseconds: totalMilliseconds, domNodes: document.nodeCount,
        displayCommands: displayList.commands.count, responseBytes: html.utf8.count),
      stylesheets: sheets, images: [:], scripts: scripts, scriptErrors: scriptErrors,
      imageErrors: imageErrors)
    let host = PageScriptHost(
      document: document, localStorage: storage.localStorage(for: originKey(url)),
      network: network)
    configureRuntime(host.runtime, page: &page, loaded: loaded, jar: jar, network: network)
    let mutationVersion = document.mutationVersion
    loaded.scriptErrors.append(contentsOf: host.run(scripts))
    host.pump()
    let runtime = host.runtime
    if document.mutationVersion != mutationVersion {
      let restyled = StyleResolver.resolve(
        document: document, stylesheets: sheets, viewport: viewport)
      let relayout = LayoutEngine().layout(restyled, viewport: viewport)
      loaded.styledDocument = restyled
      loaded.layout = relayout
      loaded.displayList = DisplayListBuilder.build(document: document, layout: relayout)
      loaded.title = document.documentTitle()
    }
    page.styleBox?.styled = loaded.styledDocument
    return (loaded, runtime)
  }

  private func restoreDiscarded(pageID: PageID) async throws {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID]
    else { throw BrowserRuntimeError.pageNotFound(pageID) }
    guard page.loaded == nil else { return }
    if let html = page.lastHTML {
      let url =
        page.history.indices.contains(page.historyIndex)
        ? page.history[page.historyIndex] : URL(string: "https://localhost/")!
      let (loaded, runtime) = buildLoaded(
        html: html, url: url, viewport: page.viewport, storage: context.storage,
        network: context.network, page: &page, jar: context.network.cookieJar)
      page.loaded = loaded
      page.javascript = runtime
      page.networkLog.append(
        NetworkLogEntry(
          request: RequestID(rawValue: requestCounter.next()), navigation: loaded.navigationID,
          url: url.absoluteString, statusCode: loaded.statusCode,
          durationMilliseconds: loaded.metrics.totalMilliseconds, fromCache: false))
      page.networkLog = Array(page.networkLog.suffix(32))
      context.pages[pageID] = page
      contexts[contextID] = context
      return
    }
    if page.history.indices.contains(page.historyIndex) {
      let url = page.history[page.historyIndex]
      context.pages[pageID] = page
      contexts[contextID] = context
      _ = try await performNavigation(
        pageID: pageID, request: HTTPRequest(url: url), history: .preserve)
      return
    }
    throw BrowserRuntimeError.pageNotLoaded(pageID)
  }

  private func refreshPage(_ pageID: PageID) throws {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID], var loaded = page.loaded
    else { throw BrowserRuntimeError.pageNotFound(pageID) }
    let styled = StyleResolver.resolve(
      document: loaded.document, stylesheets: loaded.stylesheets, viewport: page.viewport)
    let layout = LayoutEngine().layout(styled, viewport: page.viewport)
    let display = DisplayListBuilder.build(
      document: loaded.document, layout: layout, images: loaded.images)
    loaded.styledDocument = styled
    loaded.layout = layout
    loaded.displayList = display
    loaded.title = loaded.document.documentTitle()
    loaded.metrics.domNodes = loaded.document.nodeCount
    loaded.metrics.displayCommands = display.commands.count
    page.loaded = loaded
    page.lastActive = nowSeconds()
    context.pages[pageID] = page
    contexts[contextID] = context
  }

  private func makeInspectedNode(_ id: NodeID, loaded: LoadedPage) -> InspectedNode? {
    guard let node = loaded.document.node(id) else { return nil }
    let role = DOMSemantics.role(for: node) ?? node.tagName ?? "node"
    return InspectedNode(
      id: id,
      role: role,
      name: DOMSemantics.name(for: id, in: loaded.document),
      value: node.attribute("value")
        ?? (node.tagName == "textarea" ? loaded.document.textContent(of: id) : nil),
      href: node.attribute("href"),
      enabled: node.attribute("disabled") == nil,
      editable: role == "textbox" || node.attribute("contenteditable") == "true",
      visible: loaded.styledDocument.style(for: id).display != .none
        && node.attribute("hidden") == nil,
      bounds: loaded.layout.boxes[id]?.frame
    )
  }

  private func requirePage(_ id: PageID) throws -> PageRecord {
    guard let contextID = contextID(containing: id), let page = contexts[contextID]?.pages[id]
    else { throw BrowserRuntimeError.pageNotFound(id) }
    return page
  }

  private func requireContext(_ id: ContextID) throws -> ContextRecord {
    guard let context = contexts[id] else { throw BrowserRuntimeError.contextNotFound(id) }
    return context
  }

  private func contextID(containing pageID: PageID) -> ContextID? {
    contexts.first(where: { $0.value.pages[pageID] != nil })?.key
  }

  private func info(for page: PageRecord) -> BrowserPageInfo {
    BrowserPageInfo(
      id: page.id,
      contextID: page.contextID,
      url: page.loaded?.url,
      title: page.loaded?.title ?? "",
      viewport: page.viewport,
      loaded: page.loaded != nil,
      historyIndex: page.historyIndex,
      historyCount: page.history.count
    )
  }

  private func normalized(_ size: Size) -> Size {
    Size(width: min(16384, max(1, size.width)), height: min(16384, max(1, size.height)))
  }

  private func ancestor(named tag: String, from start: NodeID, document: DOMDocument) -> NodeID? {
    var current: NodeID? = start
    while let id = current {
      guard let node = document.node(id) else { return nil }
      if node.tagName == tag { return id }
      current = node.parent
    }
    return nil
  }

  private func isSubmitControl(_ node: DOMNode) -> Bool {
    if node.tagName == "button" {
      return (node.attribute("type") ?? "submit").lowercased() == "submit"
    }
    if node.tagName == "input" {
      let type = (node.attribute("type") ?? "text").lowercased()
      return type == "submit" || type == "image"
    }
    return false
  }

  private func toggleCheckbox(_ id: NodeID, document: DOMDocument) {
    if document.node(id)?.attribute("checked") == nil {
      document.setAttribute("checked", value: "", on: id)
    } else {
      document.removeAttribute("checked", from: id)
    }
  }

  private func toggleRadio(_ id: NodeID, document: DOMDocument) {
    guard let node = document.node(id) else { return }
    let name = node.attribute("name")
    if let name {
      for candidate in document.elements(named: "input") {
        guard candidate != id, let other = document.node(candidate),
          (other.attribute("type") ?? "text").lowercased() == "radio",
          other.attribute("name") == name
        else { continue }
        document.removeAttribute("checked", from: candidate)
      }
    }
    document.setAttribute("checked", value: "", on: id)
  }

  private func currentValue(_ id: NodeID, document: DOMDocument) -> String {
    guard let node = document.node(id) else { return "" }
    if let value = node.attribute("value") { return value }
    if node.tagName == "textarea" || node.attribute("contenteditable") == "true" {
      return document.textContent(of: id)
    }
    return ""
  }

  private func setControlValue(_ value: String, nodeID: NodeID, document: DOMDocument) {
    guard let node = document.node(nodeID) else { return }
    if node.attribute("contenteditable") == "true" {
      if let textNode = node.children.first(where: { child in
        guard let childNode = document.node(child) else { return false }
        if case .text = childNode.kind { return true }
        return false
      }) {
        document.setText(value, on: textNode)
      } else {
        let textNode = document.createText(value)
        document.appendChild(textNode, to: nodeID)
      }
    } else {
      document.setAttribute("value", value: value, on: nodeID)
    }
  }

  private func dispatchMutationEvent(
    _ type: String, page: PageRecord, nodeID: NodeID, document: DOMDocument
  ) throws {
    guard let runtime = page.javascript else { return }
    do { _ = try runtime.dispatchEvent(type: type, target: nodeID) } catch {
      throw BrowserRuntimeError.javascript(String(describing: error))
    }
  }

  private func formRequest(formID: NodeID, activatedNodeID: NodeID, page: LoadedPage) throws
    -> HTTPRequest
  {
    guard let form = page.document.node(formID) else {
      throw BrowserRuntimeError.invalidForm("Form disappeared before submission")
    }
    let actionValue = form.attribute("action") ?? page.url.absoluteString
    guard let action = URL(string: actionValue, relativeTo: page.url)?.absoluteURL else {
      throw BrowserRuntimeError.invalidForm("Invalid form action")
    }
    let method = (form.attribute("method") ?? "get").lowercased()
    let controls = formValues(
      formID: formID, activatedNodeID: activatedNodeID, document: page.document)
    let encoded = controls.map { "\(formEncode($0.0))=\(formEncode($0.1))" }.joined(separator: "&")

    if method == "post" {
      return HTTPRequest(
        url: action,
        method: .post,
        headers: ["Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"],
        body: Data(encoded.utf8),
        cachePolicy: .reloadIgnoringCache
      )
    }

    guard method == "get" || method.isEmpty else {
      throw BrowserRuntimeError.invalidForm("Unsupported form method: \(method)")
    }
    var components = URLComponents(url: action, resolvingAgainstBaseURL: true)
    let existing = components?.percentEncodedQuery
    components?.percentEncodedQuery = [existing, encoded].compactMap { value in
      guard let value, !value.isEmpty else { return nil }
      return value
    }.joined(separator: "&")
    guard let url = components?.url else {
      throw BrowserRuntimeError.invalidForm("Could not construct form URL")
    }
    return HTTPRequest(url: url)
  }

  private func formValues(formID: NodeID, activatedNodeID: NodeID, document: DOMDocument) -> [(
    String, String
  )] {
    var values: [(String, String)] = []
    for id in document.depthFirst(from: formID) {
      guard let node = document.node(id), let tag = node.tagName, let name = node.attribute("name"),
        !name.isEmpty, node.attribute("disabled") == nil
      else { continue }
      switch tag {
      case "input":
        let type = (node.attribute("type") ?? "text").lowercased()
        if ["button", "reset", "file"].contains(type) { continue }
        if (type == "checkbox" || type == "radio") && node.attribute("checked") == nil { continue }
        if (type == "submit" || type == "image") && id != activatedNodeID { continue }
        values.append(
          (name, node.attribute("value") ?? ((type == "checkbox" || type == "radio") ? "on" : "")))
      case "textarea":
        values.append((name, node.attribute("value") ?? document.textContent(of: id)))
      case "select":
        let options = document.depthFirst(from: id).filter {
          document.node($0)?.tagName == "option"
        }
        let selected = options.filter { document.node($0)?.attribute("selected") != nil }
        for option in selected.isEmpty ? Array(options.prefix(1)) : selected {
          guard let optionNode = document.node(option) else { continue }
          values.append((name, optionNode.attribute("value") ?? document.textContent(of: option)))
        }
      case "button":
        if id == activatedNodeID {
          values.append((name, node.attribute("value") ?? document.textContent(of: id)))
        }
      default:
        break
      }
    }
    return values
  }

  private func srcsetCandidates(_ srcset: String?, baseURL: URL) -> [URL] {
    guard let srcset, !srcset.isEmpty else { return [] }
    var result: [URL] = []
    for candidate in srcset.split(separator: ",") {
      let token = candidate.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
      guard let token, !token.isEmpty,
        let url = URL(string: token, relativeTo: baseURL)?.absoluteURL
      else { continue }
      result.append(url)
    }
    return result
  }

  private func isRedactedNode(_ id: NodeID, in document: DOMDocument) -> Bool {
    var current: NodeID? = id
    while let nodeID = current, let node = document.node(nodeID) {
      if node.attribute("data-aether-redact") != nil { return true }
      if node.tagName == "input", node.attribute("type")?.lowercased() == "password" {
        return true
      }
      current = node.parent
    }
    return false
  }

  private func isCapturable(_ frame: Rect) -> Bool {
    frame.minX.isFinite && frame.minY.isFinite && frame.width > 0 && frame.height > 0
  }

  private func cappedText(_ text: String) -> String {
    text.count > 8000 ? String(text.prefix(8000)) : text
  }

  private func selectorFor(_ id: NodeID, in document: DOMDocument) -> String {
    var parts: [String] = []
    var current: NodeID? = id
    while let nodeID = current, let node = document.node(nodeID), let tag = node.tagName {
      var part = tag
      if let idValue = node.attribute("id"), !idValue.isEmpty {
        part += "#\(String(idValue.prefix(64)))"
        parts.append(part)
        break
      }
      let classes =
        (node.attribute("class") ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init)
        .filter { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
        .prefix(3)
      for name in classes { part += ".\(name)" }
      if let parent = node.parent, let siblings = document.node(parent)?.children {
        let same = siblings.filter { document.node($0)?.tagName == tag }
        if same.count > 1, let index = same.firstIndex(of: nodeID) {
          part += ":nth-of-type(\(index + 1))"
        }
      }
      parts.append(part)
      if parts.count >= 12 { break }
      current = node.parent
    }
    return parts.reversed().joined(separator: " > ")
  }

  private func computedStyleMap(_ style: ComputedStyle) -> [String: String] {
    [
      "display": style.display.rawValue,
      "position": style.position.rawValue,
      "visibility": style.visibility.rawValue,
      "color": cssColor(style.color),
      "background-color": cssColor(style.backgroundColor),
      "font-size": "\(cssNumber(style.fontSize))px",
      "font-weight": String(style.fontWeight),
      "font-family": style.fontFamily,
      "line-height": cssNumber(style.lineHeight),
      "opacity": cssNumber(style.opacity),
      "overflow-x": style.overflowX.rawValue,
      "overflow-y": style.overflowY.rawValue,
      "z-index": String(style.zIndex),
    ]
  }

  private func cssColor(_ color: RGBAColor) -> String {
    let red = min(255, max(0, Int((color.red * 255).rounded())))
    let green = min(255, max(0, Int((color.green * 255).rounded())))
    let blue = min(255, max(0, Int((color.blue * 255).rounded())))
    if color.alpha >= 1 {
      return String(format: "#%02x%02x%02x", red, green, blue)
    }
    return "rgba(\(red), \(green), \(blue), \(cssNumber(color.alpha)))"
  }

  private func cssNumber(_ value: Double) -> String {
    guard value.isFinite else { return "0" }
    let rounded = (value * 100).rounded() / 100
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    return String(rounded)
  }

  private func originKey(_ url: URL) -> String {
    guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
      return url.absoluteString
    }
    let port = url.port.map { ":\($0)" } ?? ""
    return "\(scheme)://\(host)\(port)"
  }

  private func headerValue(_ name: String, in headers: [String: String]) -> String? {
    headers.first { $0.key.lowercased() == name.lowercased() }?.value
  }

  private func maxAgeSeconds(headers: [String: String]) -> Double {
    let control = headerValue("cache-control", in: headers)?.lowercased() ?? ""
    if let range = control.range(of: "max-age=") {
      let number = control[range.upperBound...].prefix { $0.isNumber }
      if let seconds = Double(number) { return seconds }
    }
    return 60
  }

  private func formEncode(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "*-._")
    return (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
      .replacingOccurrences(of: "%20", with: "+")
  }
}
