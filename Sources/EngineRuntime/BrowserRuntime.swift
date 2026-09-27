import BrowserEvents
import CSS
import ContentBlocker
import Diagnostics
import Display
import DOM
import EngineCore
import Foundation
import HTML
import Images
import JavaScript
import JevSearch
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

  struct PageRecord {
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
    var textSelection: NSRange? = nil
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
  }

  struct DialogRecord: Sendable {
    var id: DialogID
    var pageID: PageID
    var kind: String
    var message: String
    var defaultPrompt: String?
  }

  struct SessionRecord: Sendable {
    var id: SessionID
    var name: String
    var contextIDs: [ContextID]
    var createdAt: Double
  }

  struct DownloadRecord: Sendable {
    var id: DownloadID
    var contextID: ContextID
    var pageID: PageID?
    var url: URL
    var path: String?
    var state: String
    var bytes: Int
  }

  struct ContextRecord {
    var id: ContextID
    var name: String
    var network: NetworkSession
    var storage: StoragePartition
    var permissions: PermissionStore
    var profile: ProfileStore?
    var pages: [PageID: PageRecord]
    var downloads: [DownloadID: DownloadRecord]
    var bookmarks: [BookmarkInfo]
    var blocker: FilterEngine
  }

  struct StoredSearchProvider: Codable {
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
  let semanticSignalService: SemanticSignalService
  let searchIntelligence: SearchIntelligence
  var contexts: [ContextID: ContextRecord] = [:] {
    didSet {
      if let pageStateUpdate { publishPageState(pageStateUpdate) }
      else { publishPageStates() }
    }
  }
  var pageStateUpdate: PageID?
  var pageObservers: [UUID: AsyncStream<RuntimePageState>.Continuation] = [:]
  private var webHoveredNodes: [PageID: InspectedNode] = [:]
  private var agentInteractionObservers: [UUID: AsyncStream<AgentInteractionUpdate>.Continuation] = [:]
  private var agentInteractionSequence: UInt64 = 0
  private var lastAgentInteractionPointByPage: [PageID: Point] = [:]
  private var cancelledAgentInteractions: Set<PageID> = []
  var observedStates: [PageID: RuntimePageState] = [:]
  var navigationLoads: [PageID: Task<LoadedPage, Error>] = [:]
  var navigationEpochs: [PageID: UUID] = [:]
  var navigationErrors: [PageID: String] = [:]
  var navigationTargets: [PageID: URL] = [:]
  var semanticSignalsByPage: [PageID: SemanticPageSignals] = [:]
  var semanticObservationsByPage: [PageID: SemanticPageObservation] = [:]
  var semanticPageAssessmentTargets: [PageID: String] = [:]
  var semanticAnalysisTasks: [PageID: Task<Void, Never>] = [:]
  var semanticScheduledRevisions: [PageID: UInt64] = [:]
  var semanticTargetURLs: [PageID: String] = [:]
  var semanticImportanceCache: [PageID: (score: Double, confidence: Double, scoredAt: Double)] = [:]
  private var sessions: [SessionID: SessionRecord] = [:]
  private var maxActivePages = 8
  private var fleetMemoryBudget = 512 * 1024 * 1024
  var workspaceLeases: [ContextID: WorkspaceLeaseRecord] = [:]
  let workspaceRuntimeID = UUID()
  var workspaceLeaseReaper: Task<Void, Never>?
  /// In-flight work that a workspace lease authorizes. When a lease stops being active
  /// the runtime revokes these so a revoked workspace cannot keep being driven.
  var leaseBoundExecutions: [LeaseRevocationToken: LeaseBoundExecution] = [:]
  var branchContexts: [BranchID: ContextID] = [:]
  var contextBranches: [ContextID: BranchID] = [:]

  var webPages: [PageID: WebKitPage] = [:]
  var webPageTasks: [PageID: Task<WebKitPage, Never>] = [:]
  var webPagesPreparedForPresentation: Set<PageID> = []
  var webContexts: [ContextID: WebKitContext] = [:]
  var webStates: [PageID: WebPageState] = [:]
  var pageOwner: [PageID: ContextID] = [:]
  var webProfileIdentifiers: [ContextID: UUID] = [:]
  var webEphemeral: Set<ContextID> = []
  var webEphemeralStores: [ContextID: AnyObject] = [:]
  var webContextRules: [ContextID: AnyObject] = [:]
  var webProxyEndpoints: [ContextID: WebProxyEndpoint] = [:]
  public let events = BrowserEventBus()
  // Page events must keep the order the WebKit delegates produced them. Each
  // delegate fires on the main actor and yields here synchronously; one consumer
  // task then publishes to the bus in that order. Spawning a task per event (the
  // obvious alternative) lets actor hops reorder `navigation.finished` ahead of
  // the `document.titleChanged` that preceded it.
  let pageEventChannel = AsyncStream<(PageID, BrowserEventKind)>.makeStream(
    bufferingPolicy: .unbounded)
  let handoffs = HandoffLedger()

  let suggestService: SearchSuggestService
  let credentialSecrets: any CredentialSecretStoring

  public init(
    suggestTransport: (any SuggestTransport)? = nil,
    credentialSecrets: any CredentialSecretStoring = KeychainCredentialSecrets()
  ) {
    let semanticSignals = SemanticSignalService()
    semanticSignalService = semanticSignals
    searchIntelligence = SearchIntelligence(semanticSignals: semanticSignals)
    suggestService = SearchSuggestService(
      transport: suggestTransport ?? URLSessionSuggestTransport())
    self.credentialSecrets = credentialSecrets
    let eventStream = pageEventChannel.stream
    Task { [weak self] in
      for await (pageID, kind) in eventStream {
        await self?.publishPageEvent(kind, pageID: pageID)
      }
    }
  }

  public func observeEvents(
    filter: BrowserEventBus.Filter = .all, replay: Int = 0
  ) async -> AsyncStream<BrowserEvent> {
    await events.subscribe(filter: filter, replay: replay)
  }

  public func observeAgentInteractions() -> AsyncStream<AgentInteractionUpdate> {
    let id = UUID()
    return AsyncStream(bufferingPolicy: .bufferingNewest(128)) { continuation in
      agentInteractionObservers[id] = continuation
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeAgentInteractionObserver(id) }
      }
    }
  }

  public func cancelAgentInteraction(pageID: PageID) {
    cancelledAgentInteractions.insert(pageID)
  }

  private func removeAgentInteractionObserver(_ id: UUID) {
    agentInteractionObservers[id] = nil
  }

  @discardableResult
  func publishAgentInteraction(pageID: PageID, kind: AgentInteractionKind,
                               point: Point? = nil, viewport: Size? = nil,
                               targetLuminance: Double? = nil) -> Double {
    agentInteractionSequence &+= 1
    let movementDuration: Double
    if (kind == .move || kind == .dragging), let point,
       let previous = lastAgentInteractionPointByPage[pageID] {
      let distance = hypot(point.x - previous.x, point.y - previous.y)
      movementDuration = min(0.12, max(0.025, distance / 6_000))
    } else {
      movementDuration = 0
    }
    if (kind == .move || kind == .dragging), let point {
      lastAgentInteractionPointByPage[pageID] = point
    }
    let update = AgentInteractionUpdate(sequence: agentInteractionSequence, pageID: pageID,
      kind: kind, point: point, viewport: viewport, targetLuminance: targetLuminance,
      movementDuration: movementDuration)
    for observer in agentInteractionObservers.values { observer.yield(update) }
    return movementDuration
  }

  public func recentEvents(
    limit: Int = 200, filter: BrowserEventBus.Filter = .all, since sequence: UInt64 = 0
  ) async -> [BrowserEvent] {
    await events.recent(limit: limit, filter: filter, since: sequence)
  }

  func publishPageEvent(_ kind: BrowserEventKind, pageID: PageID) async {
    let context = contextID(containing: pageID)
    await events.publish(
      kind,
      identity: BrowserEventIdentity(
        context: context, page: pageID, branch: context.flatMap { contextBranches[$0]?.description }))
  }

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
      bookmarks: [],
      blocker: FilterEngine()
    )
    contexts[id] = record
    webProfileIdentifiers[id] = UUID()
    let publishedID = id
    let publishedName = record.name
    Task { [weak self] in
      await self?.events.publish(
        .contextCreated(name: publishedName), identity: BrowserEventIdentity(context: publishedID))
    }
    return BrowserContextInfo(id: id, name: record.name, pageCount: 0)
  }

  public func destroyContext(_ id: ContextID) async throws {
    if var lease = workspaceLeases[id], let profile = contexts[id]?.profile {
      lease.info.state = .released
      lease.info.expiresAt = nowSeconds()
      lease.runtimeID = workspaceRuntimeID
      try persistWorkspaceLease(lease, profile: profile)
      workspaceLeases[id] = lease
    }
    guard let removed = contexts.removeValue(forKey: id) else {
      throw BrowserRuntimeError.contextNotFound(id)
    }
    if let branch = contextBranches.removeValue(forKey: id) {
      branchContexts[branch] = nil
    }
    removed.profile?.close()
    workspaceLeases[id] = nil
    for pageID in removed.pages.keys {
      discardSemanticState(for: pageID)
      if let page = webPages.removeValue(forKey: pageID) { await page.close() }
      webStates[pageID] = nil
      pageOwner[pageID] = nil
      webPagesPreparedForPresentation.remove(pageID)
    }
    await events.publish(
      .contextDestroyed(name: removed.name), identity: BrowserEventIdentity(context: id))
    webContexts[id] = nil
    webProfileIdentifiers[id] = nil
    webEphemeral.remove(id)
    webContextRules[id] = nil
    webProxyEndpoints[id] = nil
    await purgeEphemeralStore(for: id)
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
    if let profileID = UUID(uuidString: directory.lastPathComponent) {
      webProfileIdentifiers[contextID] = profileID
    }
    let profile = try ProfileStore.open(directory: directory)
    do {
      try await attachProfile(profile, contextID: contextID)
      try restoreWorkspaceLease(contextID: contextID, profile: profile)
      if let originData = try profile.getKV(
        scope: BranchKV.branchScope, key: BranchKV.originKey),
        let origin = try? JSONDecoder().decode(BranchOriginRecord.self, from: originData)
      {
        contextBranches[contextID] = origin.branch
        branchContexts[origin.branch] = contextID
      }
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
    // Production navigations render in WKWebView, which owns HTTP caching
    // in its website data store (proper ETag/age revalidation, so a
    // redesigned site is never served stale). Aether's duplicate response
    // cache is purged instead of restored: it never serves a page.
    try profile.dropResponseCache()
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
        pageOwner[id] = contextID
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
    restoreHumanRequests(contextID: contextID)
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
    let stored = context.storage.snapshotAll().flatMap { origin, values in
      values.map { LocalStorageRow(origin: origin, key: $0.key, value: $0.value) }
    }
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
    let decisions = await context.permissions.snapshot()
    let permissionRows = decisions.flatMap { origin, map in
      map.map {
        PermissionRow(
          origin: origin.description, permission: $0.key.rawValue,
          decision: $0.value.rawValue)
      }
    }
    let bookmarkRows = context.bookmarks.map { bookmark in
      BookmarkRow(
        url: bookmark.url, title: bookmark.title,
        createdAt: Date(timeIntervalSince1970: bookmark.createdAt))
    }
    let downloadRecords = context.downloads.values.sorted { $0.id.rawValue < $1.id.rawValue }.map {
      PersistedDownload(
        id: $0.id.rawValue, url: $0.url.absoluteString, path: $0.path, state: $0.state,
        bytes: $0.bytes)
    }
    // Hashing, blob file I/O, and SQLite commits run off the actor so a
    // checkpoint never serializes behind the next navigation. Call order
    // is still FIFO through the actor, and awaiting the value preserves
    // shutdown durability. The duplicate HTTP response cache is gone:
    // WKWebView owns page caching with real revalidation.
    try await Task.detached(priority: .utility) {
      try profile.saveCheckpointTables(
        cookies: cookies,
        localStorage: stored,
        history: historyRows,
        sessionPages: sessionRows,
        permissions: permissionRows,
        bookmarks: bookmarkRows,
        cacheEntries: nil)
      try profile.setKV(
        scope: "downloads", key: "all", value: try JSONEncoder().encode(downloadRecords))
    }.value
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
      guard context.bookmarks[index].title != title else {
        return context.bookmarks[index]
      }
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

  public func searchCompletions(prefix: String, limit: Int = 10, endpoint: URL? = nil) async
    -> [String]
  {
    let provider = endpoint.map { SearchProvider(endpoint: $0) } ?? .defaultProvider
    guard let suggest = provider.suggestEndpoint else { return [] }
    return await suggestService.completions(endpoint: suggest, prefix: prefix, limit: limit)
  }

  public func warmSearchSuggestions(endpoint: URL? = nil) async {
    let provider = endpoint.map { SearchProvider(endpoint: $0) } ?? .defaultProvider
    guard let suggest = provider.suggestEndpoint else { return }
    await suggestService.warm(endpoint: suggest)
  }

  public func suggestSnapshot() async -> SearchSuggestService.Snapshot {
    await suggestService.snapshot()
  }

  public func suggestNavigation(
    contextID: ContextID, prefix: String, limit: Int = 8, includeNetwork: Bool = true,
    endpoint: URL? = nil
  ) async throws -> [NavigationSuggestion] {
    guard let context = contexts[contextID] else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    let raw = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else {
      throw BrowserRuntimeError.invalidNavigation("A suggestion prefix is required")
    }
    guard limit >= 1 && limit <= 50 else {
      throw BrowserRuntimeError.invalidNavigation("Suggestion limit must be 1 through 50")
    }
    let needle = raw.lowercased()
    let provider = endpoint.map { SearchProvider(endpoint: $0) }
      ?? (try? searchProvider(contextID: contextID))
    var ranked: [RankedNavigationSuggestion] = []
    if let typed = Self.typedAddress(raw), let url = URL(string: typed) {
      ranked.append(
        RankedNavigationSuggestion(
          suggestion: NavigationSuggestion(kind: "url", url: url.absoluteString), score: 400))
    }
    for bookmark in context.bookmarks {
      guard let score = Self.matchScore(needle: needle, url: bookmark.url, title: bookmark.title)
      else { continue }
      ranked.append(
        RankedNavigationSuggestion(
          suggestion: NavigationSuggestion(
            kind: "bookmark", url: bookmark.url, title: bookmark.title),
          score: score + 40))
    }
    var recency = 0
    for page in context.pages.values.sorted(by: { $0.lastActive > $1.lastActive }) {
      for url in page.history.reversed() {
        recency += 1
        let absolute = url.absoluteString
        guard let score = Self.matchScore(needle: needle, url: absolute, title: nil) else {
          continue
        }
        ranked.append(
          RankedNavigationSuggestion(
            suggestion: NavigationSuggestion(kind: "history", url: absolute),
            score: score + 20 - Double(min(recency, 20))))
      }
    }
    if includeNetwork, let provider, let suggest = provider.suggestEndpoint {
      let completions = await suggestService.completions(
        endpoint: suggest, prefix: raw, limit: limit)
      for (index, completion) in completions.enumerated() {
        guard let url = try? provider.searchURL(for: completion) else { continue }
        ranked.append(
          RankedNavigationSuggestion(
            suggestion: NavigationSuggestion(
              kind: "search", url: url.absoluteString, title: completion),
            score: 240 - Double(index)))
      }
    }
    return Self.rank(ranked, limit: limit)
  }

  static func rank(_ candidates: [RankedNavigationSuggestion], limit: Int) -> [NavigationSuggestion] {
    var seenURL = Set<String>()
    var seenText = Set<String>()
    var result: [NavigationSuggestion] = []
    for candidate in candidates.sorted(by: { $0.score > $1.score }) {
      let url = candidate.suggestion.url
      guard seenURL.insert(url.lowercased()).inserted else { continue }
      if let title = candidate.suggestion.title, !title.isEmpty {
        let key = candidate.suggestion.kind + "|" + title.lowercased()
        guard seenText.insert(key).inserted else { continue }
      }
      result.append(candidate.suggestion)
      if result.count == limit { break }
    }
    return result
  }

  static func typedAddress(_ raw: String) -> String? {
    if raw.contains("://") {
      guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
        ["http", "https"].contains(scheme), url.host?.isEmpty == false,
        url.user == nil, url.password == nil
      else { return nil }
      return url.absoluteString
    }
    guard !raw.contains(where: { $0.isWhitespace }),
      raw.contains(".") || raw.lowercased().hasPrefix("localhost")
    else { return nil }
    guard let url = URL(string: "https://" + raw), let host = url.host, !host.isEmpty,
      host.contains(".") || host.lowercased() == "localhost", url.user == nil, url.password == nil
    else { return nil }
    return url.absoluteString
  }

  static func matchScore(needle: String, url: String, title: String?) -> Double? {
    guard let host = URL(string: url)?.host?.lowercased() else {
      let haystack = (title ?? url).lowercased()
      guard haystack.contains(needle) else { return nil }
      return 80
    }
    let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    if host.hasPrefix(needle) || bare.hasPrefix(needle) { return 300 }
    if let title, title.lowercased().hasPrefix(needle) { return 220 }
    if title?.lowercased().contains(needle) == true { return 120 }
    if url.lowercased().contains(needle) { return 80 }
    return nil
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
    pageStateUpdate = id
    contexts[contextID] = context
    pageStateUpdate = nil
    pageOwner[id] = contextID
    Task { [weak self] in
      await self?.publishPageEvent(.pageCreated(url: nil), pageID: id)
      _ = try? await self?.webPage(id)
    }
    return info(for: page)
  }

  public func closePage(_ pageID: PageID) async throws {
    guard let contextID = contextID(containing: pageID) else {
      throw BrowserRuntimeError.pageNotFound(pageID)
    }
    await stopNavigation(pageID: pageID)
    await publishPageEvent(.pageClosed(reason: "closed"), pageID: pageID)
    discardSemanticState(for: pageID)
    if let page = webPages.removeValue(forKey: pageID) { await page.close() }
    webStates[pageID] = nil
    pageOwner[pageID] = nil
    webPagesPreparedForPresentation.remove(pageID)
    contexts[contextID]?.pages.removeValue(forKey: pageID)
  }

  public func suspendPage(_ pageID: PageID) async throws -> BrowserPageInfo {
    guard let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID]
    else { throw BrowserRuntimeError.pageNotFound(pageID) }
    semanticAnalysisTasks.removeValue(forKey: pageID)?.cancel()
    semanticScheduledRevisions[pageID] = nil
    if let view = webPages.removeValue(forKey: pageID) { await view.close() }
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
  public func navigate(pageID: PageID, to url: URL, settle: PageReadiness = .complete) async throws -> BrowserPageInfo {
    return try await navigateWeb(pageID: pageID, request: HTTPRequest(url: url), settle: settle)
  }

  @discardableResult
  public func navigate(pageID: PageID, request: HTTPRequest, settle: PageReadiness = .complete) async throws -> BrowserPageInfo {
    return try await navigateWeb(pageID: pageID, request: request, settle: settle)
  }

  @discardableResult
  public func goBack(pageID: PageID, settle: PageReadiness = .complete) async throws -> BrowserPageInfo {
    try await webPage(pageID).back(settle: settle)
    return try await synchronizedWebInfo(pageID)
  }

  @discardableResult
  public func goForward(pageID: PageID, settle: PageReadiness = .complete) async throws -> BrowserPageInfo {
    try await webPage(pageID).forward(settle: settle)
    return try await synchronizedWebInfo(pageID)
  }

  @discardableResult
  public func reload(pageID: PageID, bypassCache: Bool = false, settle: PageReadiness = .complete)
    async throws -> BrowserPageInfo
  {
    try await webPage(pageID).reload(bypassCache: bypassCache, settle: settle)
    return try await synchronizedWebInfo(pageID)
  }

  public func inspect(pageID: PageID) async throws -> PageInspection {
    let nodes = try await webPage(pageID).query("a,button,input,textarea,select,[role],[contenteditable=true]")
    return PageInspection(page: try pageInfo(pageID), nodes: nodes)
  }

  public func snapshot(pageID: PageID, limit: Int = 20000) async throws -> PageSnapshot {
    return try await webPage(pageID).snapshot(info: pageInfo(pageID), limit: limit)
  }

  public func query(pageID: PageID, selector: String) async throws -> InspectedNode? {
    return try await webPage(pageID).query(selector).first
  }

  public func queryAll(pageID: PageID, selector: String) async throws -> [InspectedNode] {
    return try await webPage(pageID).query(selector)
  }

  public func waitForSelector(
    pageID: PageID, selector: String, condition: SelectorWaitCondition = .visible,
    timeoutMilliseconds: UInt64 = 5_000, pollMilliseconds: UInt64 = 25
  ) async throws -> InspectedNode? {
    let clock = ContinuousClock()
    let started = clock.now
    while true {
      let node = try await query(pageID: pageID, selector: selector)
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
    let targetPage = try await webPage(pageID)
    var target = try await targetPage.interactionTarget(nodeID)
    var luminance = await targetPage.sampleLuminance(at: target) ?? target.luminance
    if target.didScroll { publishAgentInteraction(pageID: pageID, kind: .scrolling) }
    var point = Point(x: target.x, y: target.y)
    var viewport = Size(width: target.viewportWidth, height: target.viewportHeight)
    var movementDuration = publishAgentInteraction(pageID: pageID, kind: .move, point: point,
      viewport: viewport, targetLuminance: luminance)
    try await Task.sleep(for: .seconds(max(1.0 / 60.0, movementDuration)))
    let movedNativePointer = await targetPage.moveNativePointer(to: target)
    if movedNativePointer {
      publishAgentInteraction(pageID: pageID,
        kind: target.interactive ? .pointer : .hover, point: point,
        viewport: viewport, targetLuminance: luminance)
      let settled = try await targetPage.interactionTarget(nodeID)
      let correction = hypot(settled.x - target.x, settled.y - target.y)
      if correction > 0.5 {
        target = settled
        luminance = await targetPage.sampleLuminance(at: settled) ?? settled.luminance
        if settled.didScroll { publishAgentInteraction(pageID: pageID, kind: .scrolling) }
        point = Point(x: settled.x, y: settled.y)
        viewport = Size(width: settled.viewportWidth, height: settled.viewportHeight)
        movementDuration = publishAgentInteraction(pageID: pageID, kind: .move, point: point,
          viewport: viewport, targetLuminance: luminance)
        try await Task.sleep(for: .seconds(max(1.0 / 60.0, movementDuration)))
        _ = await targetPage.moveNativePointer(to: settled)
        publishAgentInteraction(pageID: pageID,
          kind: settled.interactive ? .pointer : .hover, point: point,
          viewport: viewport, targetLuminance: luminance)
      }
    }
    publishAgentInteraction(pageID: pageID, kind: .click, point: point,
      viewport: viewport, targetLuminance: luminance)
    try await Task.sleep(for: .seconds(1.0 / 60.0))
    let nativeClickCompleted = movedNativePointer
      ? await targetPage.clickNativePointer(at: target) : false
    if !nativeClickCompleted {
      try await targetPage.click(nodeID)
    }
    return try await synchronizedWebInfo(pageID)
  }

  public func drag(pageID: PageID, from start: Point, to end: Point) async throws {
    guard [start.x, start.y, end.x, end.y].allSatisfy(\.isFinite) else {
      throw BrowserRuntimeError.invalidState("Invalid drag coordinates")
    }
    let page = try await webPage(pageID)
    let viewport = try await page.viewportSize()
    guard await page.canSendNativePointer() else {
      throw BrowserRuntimeError.invalidState("Dragging requires a visible WebKit page")
    }
    cancelledAgentInteractions.remove(pageID)
    guard start.x >= 0, start.y >= 0, end.x >= 0, end.y >= 0,
          start.x < viewport.width, end.x < viewport.width,
          start.y < viewport.height, end.y < viewport.height else {
      throw BrowserRuntimeError.invalidState("Drag coordinates are outside the page viewport")
    }
    let origin = await page.dragTarget(start, viewport: viewport)
    let destination = await page.dragTarget(end, viewport: viewport)
    let sourceLuminance = await page.sampleLuminance(at: origin) ?? 1
    let sourceDuration = publishAgentInteraction(pageID: pageID, kind: .move, point: start,
      viewport: viewport, targetLuminance: sourceLuminance)
    try await Task.sleep(for: .seconds(max(1.0 / 60.0, sourceDuration)))
    guard !cancelledAgentInteractions.contains(pageID) else { throw CancellationError() }
    guard await page.moveNativePointer(to: origin), await page.beginNativeDrag(at: origin) else {
      throw BrowserRuntimeError.invalidState("Dragging requires a visible WebKit page")
    }
    let distance = hypot(end.x - start.x, end.y - start.y)
    let steps = max(1, min(90, Int(ceil(distance / 24))))
    var lastTarget = origin
    do {
      for step in 1...steps {
        try Task.checkCancellation()
        guard !cancelledAgentInteractions.contains(pageID) else { throw CancellationError() }
        let fraction = Double(step) / Double(steps)
        let point = Point(x: start.x + (end.x - start.x) * fraction,
          y: start.y + (end.y - start.y) * fraction)
        let target = await page.dragTarget(point, viewport: viewport)
        let luminance = await page.sampleLuminance(at: target) ?? sourceLuminance
        let duration = publishAgentInteraction(pageID: pageID, kind: .dragging,
          point: point, viewport: viewport, targetLuminance: luminance)
        try await Task.sleep(for: .seconds(max(1.0 / 60.0, duration)))
        guard !cancelledAgentInteractions.contains(pageID) else { throw CancellationError() }
        guard await page.dragNativePointer(to: target) else {
          throw BrowserRuntimeError.invalidState("WebKit ended the drag before the target")
        }
        lastTarget = target
      }
      await page.endNativeDrag(at: lastTarget)
      cancelledAgentInteractions.remove(pageID)
      publishAgentInteraction(pageID: pageID, kind: .pointer, point: end,
        viewport: viewport, targetLuminance: await page.sampleLuminance(at: destination) ?? sourceLuminance)
    } catch {
      await page.endNativeDrag(at: lastTarget)
      throw error
    }
  }

  public func type(pageID: PageID, nodeID: NodeID, text: String, append: Bool = false) async throws {
    let page = try await webPage(pageID)
    let target = try await page.interactionTarget(nodeID)
    let luminance = await page.sampleLuminance(at: target) ?? target.luminance
    if target.didScroll { publishAgentInteraction(pageID: pageID, kind: .scrolling) }
    let point = Point(x: target.x, y: target.y)
    let viewport = Size(width: target.viewportWidth, height: target.viewportHeight)
    let movementDuration = publishAgentInteraction(pageID: pageID, kind: .move, point: point,
      viewport: viewport, targetLuminance: luminance)
    try await Task.sleep(for: .seconds(max(1.0 / 60.0, movementDuration)))
    _ = await page.moveNativePointer(to: target)
    publishAgentInteraction(pageID: pageID, kind: .typing, point: point,
      viewport: viewport, targetLuminance: luminance)
    try await page.fill(nodeID, value: text, append: append)
  }

  public func setValue(pageID: PageID, nodeID: NodeID, value: String) async throws {
    try await type(pageID: pageID, nodeID: nodeID, text: value, append: false)
  }

  public func evaluate(pageID: PageID, source: String) async throws -> JavaScriptResult {
    return try await webPage(pageID).evaluate(source)
  }

  public func render(pageID: PageID, origin: Point = .zero) async throws -> PixelBuffer {
    return try await webPage(pageID).pixels()
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

  public func captureState(pageID: PageID) async throws -> CapturePageState {
    return try await webPage(pageID).captureState()
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
    return try await webPage(pageID).captureDocument(includeComputedStyles: includeComputedStyles, redactSensitive: redactSensitive)
  }

  public func pageInfo(_ pageID: PageID) throws -> BrowserPageInfo {
    info(for: try requirePage(pageID))
  }

  public func resize(pageID: PageID, viewport: Size) async throws -> BrowserPageInfo {
    let size = normalized(viewport)
    try await webPage(pageID).resize(size)
    return try await synchronizedWebInfo(pageID)
  }

  public func loadHTML(pageID: PageID, html: String, url: URL) async throws -> BrowserPageInfo {
    try await webPage(pageID).loadHTML(html, url: url)
    let info = try await synchronizedWebInfo(pageID)
    if let contextID = contextID(containing: pageID), var context = contexts[contextID],
      var page = context.pages[pageID]
    {
      page.lastHTML = html
      context.pages[pageID] = page
      contexts[contextID] = context
    }
    return info
  }

  public func lifecycleState(pageID: PageID) throws -> PageLifecycleState {
    try requirePage(pageID).lifecycle
  }

  public func setLifecycle(pageID: PageID, state: PageLifecycleState) async throws
    -> BrowserPageInfo
  {
    var record = try requirePage(pageID)
    if state == .active || state == .background || state == .suspended {
      record.lifecycle = state
      contexts[record.contextID]?.pages[pageID] = record
      if state == .active { try await restoreWebContent(pageID) }
      return try pageInfo(pageID)
    }
    record.lifecycle = state
    contexts[record.contextID]?.pages[pageID] = record
    if state == .discarded {
      if let view = webPages.removeValue(forKey: pageID) { await view.close() }
      webStates[pageID] = nil
    }
    return try pageInfo(pageID)
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
        let measured = estimatedBytes(of: page)
        let bytes = measured > 0 ? measured : (webPages[page.id] == nil ? 0 : 8 * 1024 * 1024)
        candidates.append(
          FleetCandidate(
            page: page.id.rawValue, importance: importance(of: page), lastActive: page.lastActive,
            estimatedBytes: bytes))
      }
    }
    for index in candidates.indices {
      let pageID = PageID(rawValue: candidates[index].page)
      guard let owner = pageOwner[pageID], !webEphemeral.contains(owner),
        let cached = semanticImportanceCache[pageID], now - cached.scoredAt < 600,
        cached.confidence >= 0.55 else { continue }
      candidates[index].importance += (cached.score / 4.0 - 0.5) * 20
    }
    var plan = fleetPlan(candidates, now: now)
    guard candidates.contains(where: { plan.action(for: $0.page) != .keep }) else { return [:] }

    for index in candidates.indices {
      let pageID = PageID(rawValue: candidates[index].page)
      if await hibernationProtection(for: pageID) { candidates[index].pinned = true }
    }
    plan = fleetPlan(candidates, now: now)

    if candidates.contains(where: { plan.action(for: $0.page) != .keep }) {
      let inputs = candidates.compactMap { candidate -> SemanticTabImportanceInput? in
        let pageID = PageID(rawValue: candidate.page)
        guard !candidate.pinned,
          let owner = pageOwner[pageID], !webEphemeral.contains(owner),
          semanticImportanceCache[pageID].map({ now - $0.scoredAt >= 600 }) ?? true,
          let record = contexts[owner]?.pages[pageID] else { return nil }
        return importanceInput(for: record)
      }
      if !inputs.isEmpty {
        let scores = await semanticSignalService.scoreTabImportance(inputs)
        for result in scores where result.confidence >= 0.55 {
          guard let rawID = UInt64(result.id) else { continue }
          let pageID = PageID(rawValue: rawID)
          semanticImportanceCache[pageID] =
            (score: result.score, confidence: result.confidence, scoredAt: now)
          if let index = candidates.firstIndex(where: { $0.page == rawID }) {
            candidates[index].importance += (result.score / 4.0 - 0.5) * 20
          }
          var signals = semanticSignalsByPage[pageID] ?? SemanticPageSignals()
          signals.tabImportanceScore = result.score
          signals.tabImportanceConfidence = result.confidence
          semanticSignalsByPage[pageID] = signals
          publishPageState(pageID)
        }
        plan = fleetPlan(candidates, now: now)
      }
    }

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

  public func hover(pageID: PageID, nodeID: NodeID) async throws -> InspectedNode? {
    if webPages[pageID] != nil {
      let page = try await webPage(pageID)
      let target = try await page.interactionTarget(nodeID)
      let luminance = await page.sampleLuminance(at: target) ?? target.luminance
      if target.didScroll { publishAgentInteraction(pageID: pageID, kind: .scrolling) }
      let point = Point(x: target.x, y: target.y)
      let viewport = Size(width: target.viewportWidth, height: target.viewportHeight)
      let movementDuration = publishAgentInteraction(pageID: pageID, kind: .move, point: point,
        viewport: viewport, targetLuminance: luminance)
      try await Task.sleep(for: .seconds(max(1.0 / 60.0, movementDuration)))
      publishAgentInteraction(pageID: pageID,
        kind: target.interactive ? .pointer : .hover, point: point,
        viewport: viewport, targetLuminance: luminance)
      if !(await page.moveNativePointer(to: target)) {
        let x = target.x
        let y = target.y
        _ = try await page.script(page.domScript("""
        (() => {
          const node = globalThis.__aetherDOM.get(\(nodeID.index));
          if (!node || !node.isConnected) throw new Error('Node is no longer attached');
          for (const type of ['mouseover', 'mouseenter', 'mousemove']) {
            node.dispatchEvent(new MouseEvent(type, {bubbles:true, cancelable:true, view:window,
              clientX:\(x), clientY:\(y), buttons:0}));
          }
        })()
        """))
      }
      storeHovered(nodeID, pageID: pageID)
      let inspected = try await page.inspectedNode(nodeID)
      if let inspected { webHoveredNodes[pageID] = inspected }
      return inspected
    }
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

  public func focus(pageID: PageID, nodeID: NodeID) async throws -> BrowserPageInfo {
    let page = try await webPage(pageID)
    let target = try await page.interactionTarget(nodeID)
    let luminance = await page.sampleLuminance(at: target) ?? target.luminance
    if target.didScroll { publishAgentInteraction(pageID: pageID, kind: .scrolling) }
    let point = Point(x: target.x, y: target.y)
    let viewport = Size(width: target.viewportWidth, height: target.viewportHeight)
    let movementDuration = publishAgentInteraction(pageID: pageID, kind: .move, point: point,
      viewport: viewport, targetLuminance: luminance)
    try await Task.sleep(for: .seconds(max(1.0 / 60.0, movementDuration)))
    _ = await page.moveNativePointer(to: target)
    publishAgentInteraction(pageID: pageID, kind: .typing, point: point,
      viewport: viewport, targetLuminance: luminance)
    try await page.nodeAction(nodeID, body: "n.focus()")
    return try pageInfo(pageID)
  }

  public func blur(pageID: PageID) async throws -> BrowserPageInfo {
    _ = try await webPage(pageID).script("document.activeElement?.blur()")
    return try pageInfo(pageID)
  }

  public func focusedNode(pageID: PageID) async throws -> InspectedNode? {
    return try await webPage(pageID).focusedNode()
  }

  public func hoveredNode(pageID: PageID) throws -> InspectedNode? {
    if let hovered = webHoveredNodes[pageID] { return hovered }
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    guard let hovered = page.hovered else { return nil }
    return makeInspectedNode(hovered, loaded: loaded)
  }

  public func scrollTo(pageID: PageID, x: Double, y: Double) async throws -> Point {
    publishAgentInteraction(pageID: pageID, kind: .scrolling)
    let result = try await webPage(pageID).scroll(x: x, y: y)
    return result
  }

  public func scrollOffset(pageID: PageID) async throws -> Point {
    return try await webPage(pageID).scrollPosition()
  }

  public func scrollIntoView(pageID: PageID, nodeID: NodeID) async throws -> Point {
    let page = try await webPage(pageID)
    publishAgentInteraction(pageID: pageID, kind: .scrolling)
    try await page.nodeAction(nodeID, body: "n.scrollIntoView({block:'center'})")
    let point = try await page.scrollPosition()
    return point
  }

  public func nodeAtPoint(pageID: PageID, x: Double, y: Double) async throws -> InspectedNode? {
    guard x.isFinite, y.isFinite else {
      throw BrowserRuntimeError.invalidState("Invalid hit-test coordinates")
    }
    if webPages[pageID] != nil {
      return try await webPage(pageID).nodeAtPoint(x: x, y: y)
    }
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    let target = Point(x: x + page.scroll.x, y: y + page.scroll.y)
    guard let id = HitTesting.node(at: target, in: loaded.layout) else { return nil }
    return makeInspectedNode(id, loaded: loaded)
  }

  public func pressKey(pageID: PageID, key: String) async throws -> String {
    if webPages[pageID] != nil {
      return try await webPage(pageID).pressKey(key)
    }
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
      _ = try await blur(pageID: pageID)
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

  public func selectOption(pageID: PageID, selectNodeID: NodeID, value: String) async throws {
    try await type(pageID: pageID, nodeID: selectNodeID, text: value)
  }

  public func fill(pageID: PageID, nodeID: NodeID, value: String) async throws {
    try await type(pageID: pageID, nodeID: nodeID, text: value)
  }

  public func submitForm(pageID: PageID, formNodeID: NodeID) async throws -> BrowserPageInfo {
    try await webPage(pageID).nodeAction(formNodeID, body: "n.requestSubmit()")
    return try await synchronizedWebInfo(pageID)
  }

  public func historyEntries(pageID: PageID) throws -> [HistoryEntry] {
    let page = try requirePage(pageID)
    return page.history.enumerated().map { index, url in
      HistoryEntry(index: index, url: url.absoluteString, current: index == page.historyIndex)
    }
  }

  public func consoleOutput(pageID: PageID) async throws -> [String] {
    _ = try requirePage(pageID)
    // WebKit-backed pages have no experimental `loaded` record; their console
    // lines are captured by the injected bridge and read back from the page.
    if let webPage = try? await webPage(pageID) {
      return await webPage.consoleLines()
    }
    let page = try requirePage(pageID)
    guard page.loaded != nil else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    return page.javascript?.consoleOutput ?? []
  }

  public func networkLogEntries(pageID: PageID) throws -> [NetworkLogEntry] {
    try requirePage(pageID).networkLog
  }

  public func mainFrame(pageID: PageID) throws -> AgentFrameInfo {
    let page = try requirePage(pageID)
    if let state = webStates[pageID] {
      guard state.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
      return AgentFrameInfo(
        id: FrameID(rawValue: pageID.rawValue), page: pageID,
        url: state.url?.absoluteString, title: state.title)
    }
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    return AgentFrameInfo(
      id: FrameID(rawValue: loaded.document.id.rawValue), page: pageID, url: loaded.url.absoluteString,
      title: loaded.title)
  }

  public func listWorkers(pageID: PageID) throws -> [WorkerID] {
    _ = try requirePage(pageID)
    return []
  }

  public func storageOrigins(contextID cid: ContextID) async throws -> [String] {
    _ = try requireContext(cid)
    var origins: [String] = []
    for id in webStates.keys where contextID(containing: id) == cid {
      guard let host = webStates[id]?.url?.host else { continue }
      let page = try await webPage(id)
      let count = try? await page.decode(Int.self, "JSON.stringify(localStorage.length)")
      if (count ?? 0) > 0 { origins.append(host) }
    }
    return origins.sorted()
  }

  private func storagePage(contextID cid: ContextID, origin: String) async throws -> WebKitPage {
    let trimmed = origin.trimmingCharacters(in: .whitespacesAndNewlines)
    let want = (URL(string: trimmed)?.host ?? trimmed).lowercased()
    for id in webStates.keys where contextID(containing: id) == cid {
      if webStates[id]?.url?.host?.lowercased() == want { return try await webPage(id) }
    }
    throw BrowserRuntimeError.invalidState("No live page for origin \(origin)")
  }

  public func storageValues(contextID: ContextID, origin: String) async throws -> [String: String] {
    let page = try await storagePage(contextID: contextID, origin: origin)
    return try await page.decode([String: String].self, "JSON.stringify(Object.assign({},localStorage))")
  }

  public func storageSet(contextID: ContextID, origin: String, key: String, value: String) async throws {
    let page = try await storagePage(contextID: contextID, origin: origin)
    _ = try await page.script(
      "localStorage.setItem(\(try WebKitPage.literal(key)),\(try WebKitPage.literal(value)))",
      isolated: false)
  }

  public func storageRemove(contextID: ContextID, origin: String, key: String) async throws {
    let page = try await storagePage(contextID: contextID, origin: origin)
    _ = try await page.script(
      "localStorage.removeItem(\(try WebKitPage.literal(key)))", isolated: false)
  }

  public func storageClear(contextID: ContextID, origin: String) async throws {
    let page = try await storagePage(contextID: contextID, origin: origin)
    _ = try await page.script("localStorage.clear()", isolated: false)
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
    await stopNavigation(pageID: pageID)
    let epoch = UUID()
    navigationEpochs[pageID] = epoch
    navigationTargets[pageID] = request.url
    navigationErrors[pageID] = nil
    let viewport = initialPage.viewport
    let load = Task { try await pipeline.load(request, viewport: viewport) }
    navigationLoads[pageID] = load
    publishPageStates()
    var loaded: LoadedPage
    do {
      loaded = try await withTaskCancellationHandler {
        try await load.value
      } onCancel: { load.cancel() }
      try Task.checkCancellation()
      guard navigationEpochs[pageID] == epoch else { throw CancellationError() }
      navigationLoads[pageID] = nil
      navigationTargets[pageID] = nil
    } catch {
      if navigationEpochs[pageID] == epoch {
        navigationLoads[pageID] = nil
        navigationTargets[pageID] = nil
        if !(error is CancellationError) { navigationErrors[pageID] = String(describing: error) }
        publishPageStates()
      }
      if error is CancellationError { throw error }
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

  func nowSeconds() -> Double { Date().timeIntervalSince1970 }

  func fleetPlan(_ candidates: [FleetCandidate], now: Double) -> FleetPlan {
    FleetScheduler.plan(candidates: candidates, maxActive: maxActivePages,
      memoryBudgetBytes: fleetMemoryBudget, now: now)
  }

  private func estimatedBytes(of page: PageRecord) -> Int {
    guard let loaded = page.loaded else {
      return webPages[page.id] != nil && webStates[page.id]?.loaded == true
        ? 8 * 1024 * 1024 : 0
    }
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
    if page.focused != id { page.textSelection = nil }
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
    page: inout PageRecord, jar: CookieJar, blocker: FilterEngine
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
        network: context.network, page: &page, jar: context.network.cookieJar,
        blocker: context.blocker)
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

  func refreshPage(_ pageID: PageID) throws {
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

  func requirePage(_ id: PageID) throws -> PageRecord {
    guard let contextID = contextID(containing: id), let page = contexts[contextID]?.pages[id]
    else { throw BrowserRuntimeError.pageNotFound(id) }
    return page
  }

  func requireContext(_ id: ContextID) throws -> ContextRecord {
    guard let context = contexts[id] else { throw BrowserRuntimeError.contextNotFound(id) }
    return context
  }

  func contextID(containing pageID: PageID) -> ContextID? {
    if let owner = pageOwner[pageID], contexts[owner]?.pages[pageID] != nil { return owner }
    guard let found = contexts.first(where: { $0.value.pages[pageID] != nil })?.key else {
      pageOwner[pageID] = nil
      return nil
    }
    pageOwner[pageID] = found
    return found
  }

  func info(for page: PageRecord) -> BrowserPageInfo {
    if let state = webStates[page.id] {
      return BrowserPageInfo(id: page.id, contextID: page.contextID, url: state.url,
        title: state.title, viewport: state.viewport, loaded: state.loaded,
        historyIndex: state.historyIndex, historyCount: state.history.count)
    }
    return BrowserPageInfo(
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

  func currentValue(_ id: NodeID, document: DOMDocument) -> String {
    guard let node = document.node(id) else { return "" }
    if let value = node.attribute("value") { return value }
    if node.tagName == "textarea" || node.attribute("contenteditable") == "true" {
      return document.textContent(of: id)
    }
    return ""
  }

  func setControlValue(_ value: String, nodeID: NodeID, document: DOMDocument) {
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

struct RankedNavigationSuggestion: Sendable {
  var suggestion: NavigationSuggestion
  var score: Double
}
