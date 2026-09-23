import AppKit
import EngineCore
import Foundation
import WebKit

struct WebPageState: Sendable, Equatable {
  let sequence: UInt64
  let url: URL?
  let title: String
  let viewport: Size
  let history: [URL]
  let historyIndex: Int
  let loading: Bool
  let loaded: Bool
  let contentReady: Bool
  let progress: Double
  let statusCode: Int
  let error: String?
}

enum WebKitNavigationErrorClass {
  case benign
  case genuine

  // WebKit reports policy-driven interruptions under two different domains
  // depending on the framework version. Both mean "this navigation did not
  // proceed", never "the site is broken".
  static let webKitDomains: Set<String> = ["WebKitErrorDomain", "WKErrorDomain"]
  static let frameLoadInterrupted = 102
  static let pluginWillHandleLoad = 204

  static func classify(_ error: Error) -> WebKitNavigationErrorClass {
    if isCancellation(error) { return .benign }
    if isFrameLoadInterrupted(error) { return .benign }
    if isPluginHandledLoad(error) { return .benign }
    return .genuine
  }

  static func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
  }

  // Redirects, superseded requests and policy changes surface as WebKit's
  // "Frame load interrupted". This is not a failure to render a website.
  static func isFrameLoadInterrupted(_ error: Error) -> Bool {
    let nsError = error as NSError
    return webKitDomains.contains(nsError.domain) && nsError.code == frameLoadInterrupted
  }

  static func isPluginHandledLoad(_ error: Error) -> Bool {
    let nsError = error as NSError
    return webKitDomains.contains(nsError.domain) && nsError.code == pluginWillHandleLoad
  }

  static func describe(_ error: Error) -> String {
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
      switch nsError.code {
      case NSURLErrorNotConnectedToInternet: return "The Internet connection appears to be offline."
      case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
        return "The server could not be found."
      case NSURLErrorCannotConnectToHost: return "The server refused the connection."
      case NSURLErrorNetworkConnectionLost: return "The connection to the server was lost."
      case NSURLErrorTimedOut: return "The server took too long to respond."
      case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
        NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateNotYetValid:
        return "A secure connection to the server could not be established."
      default: break
      }
    }
    if nsError.domain == "WebKitErrorDomain" {
      switch nsError.code {
      case 101: return "The address cannot be displayed."
      case 103: return "The page could not be reached."
      default: break
      }
    }
    return error.localizedDescription
  }
}

private struct NavigationWaiter {
  let id: UUID
  let scope: UInt64
  let commitOnly: Bool
  let continuation: CheckedContinuation<Void, Error>
}

enum WebKitNavigationProbe {
  static var enabled: Bool {
    ProcessInfo.processInfo.environment["AETHER_WEBKIT_DIAG"] != nil
  }

  static func log(_ message: @autoclosure () -> String) {
    guard enabled else { return }
    let line = "[webkit-nav] \(message())\n"
    FileHandle.standardError.write(Data(line.utf8))
  }
}


@MainActor
final class WebKitContext {
  let store: WKWebsiteDataStore
  let isEphemeral: Bool
  var rules: WKContentRuleList?

  init(identifier: UUID) {
    store = WebKitStoreCache.shared.store(for: identifier)
    isEphemeral = false
  }

  init(ephemeralStore: WKWebsiteDataStore) {
    store = ephemeralStore
    isEphemeral = true
  }

  static func ephemeral() -> WebKitContext {
    WebKitContext(ephemeralStore: WKWebsiteDataStore.nonPersistent())
  }
}

@MainActor
final class WebKitPage: NSObject, WKNavigationDelegate {
  let view: WKWebView
  let context: WebKitContext
  var generation: UInt32 = 1
  var loaded = false
  var contentReady = false
  var lastError: String?
  var statusCode = 0
  private var sequence: UInt64 = 0
  private var currentScope: UInt64 = 0
  private var committedScope: UInt64?
  private var interruptedScope: UInt64?
  private var current: WKNavigation?
  private var retired: [WKNavigation] = []
  private var halted = true
  private var publicationScheduled = false
  private var lastPublished: WebPageState?
  private var observations: [NSKeyValueObservation] = []
  private var waiters: [ObjectIdentifier: NavigationWaiter] = [:]
  private var deadlines: [ObjectIdentifier: Task<Void, Never>] = [:]
  private var scopeStartedAt: [UInt64: Date] = [:]
  private var cachedHistory: [URL] = []
  private var cachedHistoryIndex: Int = -1
  private var historyDirty = true
  private var lastProgressPublishedAt: Date = .distantPast
  private var lastPublishedProgress: Double = 0
  private(set) var committedAt: Date?

  private func elapsed(_ scope: UInt64) -> String {
    guard let start = scopeStartedAt[scope] else { return "t=?" }
    return String(format: "t=%.3fs", Date().timeIntervalSince(start))
  }

  private func probe(_ message: @autoclosure () -> String) {
    WebKitNavigationProbe.log("[scope=\(currentScope) \(message())]")
  }
  private let changed: @Sendable (WebPageState) -> Void
  var dialogs: WebKitDialogs?

  init(context: WebKitContext, viewport: Size, changed: @escaping @Sendable (WebPageState) -> Void) {
    self.context = context
    self.changed = changed
    let viewStart = WebKitNavigationProbe.enabled ? Date() : nil
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = context.store
    configuration.preferences.inactiveSchedulingPolicy = .suspend
    WebKitAppearance.install(in: configuration)
    if let rules = context.rules { configuration.userContentController.add(rules) }
    view = WKWebView(frame: NSRect(x: 0, y: 0, width: viewport.width, height: viewport.height),
      configuration: configuration)
    if let viewStart {
      let ms = Date().timeIntervalSince(viewStart) * 1000
      WebKitNavigationProbe.log(String(format: "view-alloc %.1fms", ms))
    }
    super.init()
    view.navigationDelegate = self
    view.allowsBackForwardNavigationGestures = true
    view.isInspectable = true
    dialogs = WebKitDialogs()
    view.uiDelegate = dialogs
    observations = [
      view.observe(\.url, options: [.new]) { [weak self] _, _ in self?.scheduleChange() },
      view.observe(\.title, options: [.new]) { [weak self] _, _ in self?.scheduleChange() },
      view.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
        self?.scheduleChange()
        Task { @MainActor [weak self] in
          guard let self, let scope = self.interruptedScope else { return }
          self.settleInterruptedNavigation(scope)
        }
      },
      view.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in self?.scheduleChange() },
      view.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.scheduleChange() },
      view.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.scheduleChange() }
    ]
  }

  nonisolated private func scheduleChange() {
    Task { @MainActor [weak self] in
      guard let self, !self.publicationScheduled else { return }
      self.publicationScheduled = true
      self.publish()
      self.publicationScheduled = false
    }
  }

  func state() -> WebPageState {
    sequence += 1
    if historyDirty {
      historyDirty = false
      refreshHistoryCache()
    }
    return WebPageState(sequence: sequence, url: view.url, title: view.title ?? "",
      viewport: Size(width: view.bounds.width, height: view.bounds.height),
      history: cachedHistory, historyIndex: cachedHistoryIndex,
      loading: isLoading, loaded: loaded, contentReady: contentReady,
      progress: view.estimatedProgress,
      statusCode: statusCode, error: lastError)
  }

  private func refreshHistoryCache() {
    let list = view.backForwardList
    cachedHistory =
      list.backList.map(\.url) + (list.currentItem.map { [$0.url] } ?? []) + list.forwardList.map(\.url)
    cachedHistoryIndex = list.currentItem == nil ? -1 : list.backList.count
  }

  private var isLoading: Bool {
    guard !halted else { return false }
    return view.isLoading || current != nil
  }

  func publish() {
    let value = state()
    if let previous = lastPublished,
      previous.url == value.url, previous.title == value.title,
      previous.viewport == value.viewport, previous.history == value.history,
      previous.historyIndex == value.historyIndex,       previous.loading == value.loading,
      previous.loaded == value.loaded, previous.contentReady == value.contentReady,
      previous.statusCode == value.statusCode,
      previous.error == value.error {
      let delta = abs(value.progress - lastPublishedProgress)
      let now = Date()
      if value.progress < 1.0, delta < 0.02, now.timeIntervalSince(lastProgressPublishedAt) < 0.1 { return }
      if value.progress == previous.progress { return }
      lastPublishedProgress = value.progress
      lastProgressPublishedAt = now
      lastPublished = value
      changed(value)
      return
    }
    lastPublishedProgress = value.progress
    lastProgressPublishedAt = Date()
    lastPublished = value
    changed(value)
  }

  // A fresh navigation identity never means "cancel the caller". Our own
  // navigate/back/forward/reload already cancel through begin() -> stop(), and
  // WebKit hands us a new identity for server redirects and for navigations it
  // starts itself. Pending waiters are therefore transferred, not cancelled, so
  // one waiter follows one logical navigation and a redirect resolves normally
  // instead of throwing a bogus CancellationError (which surfaced as a false
  // error over an already rendered page).
  @discardableResult
  private func track(_ navigation: WKNavigation) -> UInt64 {
    if let current, current === navigation { return currentScope }
    let nextScope = currentScope &+ 1
    let key = ObjectIdentifier(navigation)
    let pending = waiters.filter { $0.value.scope == currentScope }
    probe("track new-identity transferred=\(pending.count) url=\(view.url?.absoluteString ?? "nil") loading=\(view.isLoading)")
    for (index, entry) in pending.enumerated() {
      waiters.removeValue(forKey: entry.key)
      deadlines.removeValue(forKey: entry.key)?.cancel()
      guard index == 0 else {
        entry.value.continuation.resume(throwing: CancellationError())
        continue
      }
      waiters[key] = NavigationWaiter(
        id: entry.value.id, scope: nextScope, commitOnly: entry.value.commitOnly,
        continuation: entry.value.continuation)
      armDeadline(for: key)
    }
    current = navigation
    currentScope = nextScope
    scopeStartedAt[nextScope] = Date()
    committedScope = nil
    committedAt = nil
    interruptedScope = nil
    halted = false
    historyDirty = true
    contentReady = false
    statusCode = 0
    lastError = nil
    return currentScope
  }

  private func armDeadline(for key: ObjectIdentifier) {
    deadlines[key] = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(60)) } catch { return }
      self?.expire(key)
    }
  }

  private func isTracked(_ navigation: WKNavigation?) -> Bool {
    guard let navigation, let current else { return false }
    return current === navigation
  }

  private func endTracking(contentUsable: Bool) {
    current = nil
    halted = true
    contentReady = contentUsable
    interruptedScope = nil
  }

  private func begin(_ start: () -> WKNavigation?) -> WKNavigation? {
    stop()
    guard let navigation = start() else {
      probe("begin no-navigation-object")
      publish()
      return nil
    }
    current = navigation
    currentScope &+= 1
    scopeStartedAt[currentScope] = Date()
    committedScope = nil
    committedAt = nil
    interruptedScope = nil
    halted = false
    historyDirty = true
    contentReady = false
    statusCode = 0
    lastError = nil
    probe("begin url=\(view.url?.absoluteString ?? "nil")")
    publish()
    return navigation
  }

  func navigate(_ request: URLRequest, settle: PageReadiness = .complete) async throws {
    guard let scheme = request.url?.scheme?.lowercased(), ["http", "https", "about"].contains(scheme) else {
      throw BrowserRuntimeError.invalidNavigation("Only HTTP and HTTPS navigation is supported")
    }
    if settle == .commit, isPlainGet(request), let url = request.url {
      guard let navigation = begin({ view.load(url) }) else { return }
      try await wait(for: navigation, settle: settle)
      return
    }
    guard let navigation = begin({ view.load(request) }) else { return }
    try await wait(for: navigation, settle: settle)
  }

  private func isPlainGet(_ request: URLRequest) -> Bool {
    guard let url = request.url, url.host != nil else { return false }
    let method = request.httpMethod?.uppercased() ?? "GET"
    guard method == "GET" else { return false }
    guard request.httpBody == nil, request.httpBodyStream == nil else { return false }
    guard request.allHTTPHeaderFields?.isEmpty ?? true else { return false }
    return request.cachePolicy == .useProtocolCachePolicy
  }

  func loadHTML(_ html: String, url: URL) async throws {
    guard let navigation = begin({ view.loadHTMLString(html, baseURL: url) }) else { return }
    try await wait(for: navigation, settle: .complete)
  }

  func back(settle: PageReadiness = .complete) async throws {
    guard let navigation = begin({ view.goBack() }) else { return }
    try await wait(for: navigation, settle: settle)
  }

  func forward(settle: PageReadiness = .complete) async throws {
    guard let navigation = begin({ view.goForward() }) else { return }
    try await wait(for: navigation, settle: settle)
  }

  func reload(bypassCache: Bool, settle: PageReadiness = .complete) async throws {
    guard let navigation = begin({ bypassCache ? view.reloadFromOrigin() : view.reload() }) else { return }
    try await wait(for: navigation, settle: settle)
  }

  private func wait(for navigation: WKNavigation?, settle: PageReadiness = .complete) async throws {
    guard let navigation else { return }
    let key = ObjectIdentifier(navigation)
    let scope = currentScope
    let waiterID = UUID()
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try await withCheckedThrowingContinuation { continuation in
        waiters[key] = NavigationWaiter(
          id: waiterID, scope: scope, commitOnly: settle == .commit, continuation: continuation)
        armDeadline(for: key)
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancelWaiting(waiterID) }
    }
  }

  private func expire(_ key: ObjectIdentifier) {
    guard let waiter = waiters[key] else { return }
    probe("expire waiterScope=\(waiter.scope) committed=\(committedScope.map(String.init) ?? "nil") \(elapsed(waiter.scope))")
    // Usable content is already on screen: release the caller rather than
    // inventing a timeout failure over a page the user can read.
    if committedScope != nil || committedScope == waiter.scope {
      resolve(key)
      endTracking(contentUsable: true)
      publish()
      return
    }
    view.stopLoading()
    lastError = "The page took too long to load."
    resolve(key, error: BrowserRuntimeError.timeout(lastError ?? ""))
    endTracking(contentUsable: false)
    publish()
  }

  // Cancelling a waiter must only stop the load it belongs to. Abandoning a
  // superseded navigation previously called stopLoading() on the navigation
  // that had already replaced it, which is how a healthy page load ended up
  // interrupted.
  private func cancelWaiting(_ id: UUID) {
    guard let (key, waiter) = waiters.first(where: { $0.value.id == id }) else { return }
    probe("cancelWaiting waiterScope=\(waiter.scope)")
    let isTrackedScope = waiter.scope == currentScope
    resolve(key, error: CancellationError())
    if isTrackedScope {
      view.stopLoading()
      endTracking(contentUsable: loaded)
      publish()
    }
  }

  private func settleInterruptedNavigation(_ scope: UInt64) {
    Task { @MainActor [weak self] in
      await Task.yield()
      guard let self, self.interruptedScope == scope, self.currentScope == scope,
        !self.view.isLoading else { return }
      if let current = self.current {
        self.resolve(ObjectIdentifier(current), error: CancellationError())
      }
      self.lastError = nil
      self.endTracking(contentUsable: self.loaded)
      self.publish()
    }
  }

  private func resolve(_ key: ObjectIdentifier, error: Error? = nil) {
    deadlines.removeValue(forKey: key)?.cancel()
    guard let waiter = waiters.removeValue(forKey: key) else { return }
    if let error { waiter.continuation.resume(throwing: error) }
    else { waiter.continuation.resume() }
  }

  private func resolveCommitWaiters(_ navigation: WKNavigation) {
    let key = ObjectIdentifier(navigation)
    guard current === navigation, let waiter = waiters[key], waiter.commitOnly else { return }
    resolve(key)
  }

  func stop() {
    if current != nil || !waiters.isEmpty {
      probe("stop waiters=\(waiters.count)")
    }
    if let current {
      retired.append(current)
      if retired.count > 32 { retired.removeFirst(retired.count - 32) }
    }
    view.stopLoading()
    for key in Array(waiters.keys) { resolve(key, error: CancellationError()) }
    endTracking(contentUsable: loaded)
    publish()
  }

  func close() {
    stop()
    view.navigationDelegate = nil
    view.uiDelegate = nil
    dialogs?.close()
    observations.removeAll()
    view.removeFromSuperview()
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    guard let navigation else {
      publish()
      return
    }
    probe("didStartProvisional tracked=\(isTracked(navigation)) retired=\(retired.contains(where: { $0 === navigation })) url=\(webView.url?.absoluteString ?? "nil")")
    guard !retired.contains(where: { $0 === navigation }) else { return }
    track(navigation)
    publish()
  }

  func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
    probe("serverRedirect tracked=\(isTracked(navigation)) url=\(webView.url?.absoluteString ?? "nil")")
  }

  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    guard let navigation else { return }
    probe("didCommit tracked=\(isTracked(navigation)) url=\(webView.url?.absoluteString ?? "nil") \(elapsed(currentScope))")
    guard isTracked(navigation) else { return }
    generation &+= 1
    loaded = true
    contentReady = true
    committedScope = currentScope
    committedAt = Date()
    historyDirty = true
    lastError = nil
    publish()
    resolveCommitWaiters(navigation)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let navigation else { return }
    probe("didFinish tracked=\(isTracked(navigation)) url=\(webView.url?.absoluteString ?? "nil") \(elapsed(currentScope))")
    guard isTracked(navigation) else {
      publish()
      return
    }
    loaded = true
    lastError = nil
    resolve(ObjectIdentifier(navigation))
    endTracking(contentUsable: true)
    publish()
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    failed(navigation, error: error)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    failed(navigation, error: error)
  }

  private func failed(_ navigation: WKNavigation?, error: Error) {
    guard let navigation else {
      publish()
      return
    }
    let nsError = error as NSError
    probe("didFail tracked=\(isTracked(navigation)) domain=\(nsError.domain) code=\(nsError.code) class=\(WebKitNavigationErrorClass.classify(error)) committed=\(committedScope.map(String.init) ?? "nil") \(elapsed(currentScope))")
    let key = ObjectIdentifier(navigation)
    guard isTracked(navigation) else {
      // A superseded navigation must never touch the current page's state, but
      // its own waiter still has to be released so no caller hangs.
      if waiters[key] != nil {
        resolve(key, error: WebKitNavigationErrorClass.isCancellation(error)
          ? CancellationError() : error)
      }
      publish()
      return
    }
    // A navigation that already committed is on screen. Its document is the
    // user's page; a later interruption of that same navigation must never
    // replace rendered content with an error overlay.
    let documentOnScreen = committedScope == currentScope
    switch WebKitNavigationErrorClass.classify(error) {
    case .benign where !WebKitNavigationErrorClass.isCancellation(error):
      lastError = nil
      interruptedScope = currentScope
      settleInterruptedNavigation(currentScope)
      publish()
    case .benign:
      if documentOnScreen {
        resolve(key)
      } else {
        resolve(key, error: CancellationError())
      }
      lastError = nil
      endTracking(contentUsable: documentOnScreen || contentReady)
      publish()
    case .genuine where documentOnScreen:
      lastError = nil
      loaded = true
      resolve(key)
      endTracking(contentUsable: true)
      publish()
    case .genuine:
      lastError = WebKitNavigationErrorClass.describe(error)
      resolve(key, error: error)
      endTracking(contentUsable: false)
      publish()
    }
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    probe("processTerminated url=\(webView.url?.absoluteString ?? "nil")")
    let message = "The webpage process stopped. Reload the page to continue."
    lastError = message
    loaded = false
    contentReady = false
    committedScope = nil
    committedAt = nil
    for key in Array(waiters.keys) {
      resolve(key, error: BrowserRuntimeError.invalidState(message))
    }
    endTracking(contentUsable: false)
    publish()
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
    let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
    let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
    probe("decideAction scheme=\(scheme) mainFrame=\(mainFrame) type=\(navigationAction.navigationType.rawValue) mainNavTracked=\(mainNavTracked(navigationAction.mainFrameNavigation)) url=\(navigationAction.request.url?.absoluteString ?? "nil")")
    guard ["http", "https", "about", "blob", "data"].contains(scheme) else {
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
    let authoritativeMain = isAuthoritativeMain(response: navigationResponse)
    if navigationResponse.isForMainFrame, authoritativeMain {
      statusCode = (navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 0
    }
    let policy: WKNavigationResponsePolicy = navigationResponse.canShowMIMEType ? .allow : .download
    probe("decideResponse mainFrame=\(navigationResponse.isForMainFrame) authoritative=\(authoritativeMain) mime=\(navigationResponse.response.mimeType ?? "nil") policy=\(policy == .allow ? "allow" : "download")")
    decisionHandler(policy)
  }

  private func mainNavTracked(_ navigation: WKNavigation?) -> String {
    guard let navigation else { return "nil" }
    return isTracked(navigation) ? "tracked" : "stale"
  }

  private func isAuthoritativeMain(response: WKNavigationResponse) -> Bool {
    guard response.isForMainFrame else { return false }
    guard let mainNavigation = response.mainFrameNavigation else { return true }
    return isTracked(mainNavigation)
  }

  func resolveMainFrameDownload(action: WKNavigationAction) {
    guard action.targetFrame?.isMainFrame ?? false else { return }
    let documentOnScreen = committedScope == currentScope
    probe("downloadTerminal(action) committed=\(documentOnScreen) waiters=\(waiters.count)")
    for key in Array(waiters.keys) where waiters[key]?.scope == currentScope {
      if documentOnScreen { resolve(key) } else { resolve(key, error: CancellationError()) }
    }
    lastError = nil
    endTracking(contentUsable: documentOnScreen || contentReady)
    publish()
  }

  func resolveMainFrameDownload(response: WKNavigationResponse) {
    guard isAuthoritativeMain(response: response) else { return }
    let documentOnScreen = committedScope == currentScope
    probe("downloadTerminal committed=\(documentOnScreen) waiters=\(waiters.count)")
    for key in Array(waiters.keys) where waiters[key]?.scope == currentScope {
      if documentOnScreen { resolve(key) } else { resolve(key, error: CancellationError()) }
    }
    lastError = nil
    endTracking(contentUsable: documentOnScreen || contentReady)
    publish()
  }
}
