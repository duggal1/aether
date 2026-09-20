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
  let error: String?
}

@MainActor
final class WebKitContext {
  let store: WKWebsiteDataStore
  var rules: WKContentRuleList?

  init(identifier: UUID?) {
    store = WebKitStoreCache.shared.store(for: identifier)
  }
}

@MainActor
final class WebKitPage: NSObject, WKNavigationDelegate {
  let view: WKWebView
  let context: WebKitContext
  var generation: UInt32 = 1
  var loaded = false
  var lastError: String?
  var statusCode = 0
  private var sequence: UInt64 = 0
  private var publicationScheduled = false
  private var lastPublished: WebPageState?
  private var observations: [NSKeyValueObservation] = []
  private var pending: [ObjectIdentifier: CheckedContinuation<Void, Error>] = [:]
  private var commitPending: [ObjectIdentifier: CheckedContinuation<Void, Error>] = [:]
  private var deadlines: [ObjectIdentifier: Task<Void, Never>] = [:]
  private let changed: @Sendable (WebPageState) -> Void
  var dialogs: WebKitDialogs?

  init(context: WebKitContext, viewport: Size, changed: @escaping @Sendable (WebPageState) -> Void) {
    self.context = context
    self.changed = changed
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = context.store
    WebKitAppearance.install(in: configuration)
    if let rules = context.rules { configuration.userContentController.add(rules) }
    view = WKWebView(frame: NSRect(x: 0, y: 0, width: viewport.width, height: viewport.height),
      configuration: configuration)
    super.init()
    view.navigationDelegate = self
    view.allowsBackForwardNavigationGestures = true
    view.isInspectable = true
    dialogs = WebKitDialogs()
    view.uiDelegate = dialogs
    observations = [
      view.observe(\.url, options: [.new]) { [weak self] _, _ in self?.scheduleChange() },
      view.observe(\.title, options: [.new]) { [weak self] _, _ in self?.scheduleChange() },
      view.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.scheduleChange() },
      view.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.scheduleChange() },
      view.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.scheduleChange() }
    ]
    if let blank = URL(string: "about:blank") { view.load(URLRequest(url: blank)) }
  }

  nonisolated private func scheduleChange() {
    Task { @MainActor [weak self] in
      guard let self, !self.publicationScheduled else { return }
      self.publicationScheduled = true
      Task { @MainActor [weak self] in
        await Task.yield()
        guard let self else { return }
        self.publicationScheduled = false
        self.publish()
      }
    }
  }

  func state() -> WebPageState {
    sequence += 1
    let list = view.backForwardList
    let history = list.backList.map(\.url) + (list.currentItem.map { [$0.url] } ?? []) + list.forwardList.map(\.url)
    return WebPageState(sequence: sequence, url: view.url, title: view.title ?? "",
      viewport: Size(width: view.bounds.width, height: view.bounds.height),
      history: history, historyIndex: list.currentItem == nil ? -1 : list.backList.count,
      loading: view.isLoading, loaded: loaded, error: lastError)
  }

  func publish() {
    let value = state()
    if let previous = lastPublished,
      previous.url == value.url, previous.title == value.title,
      previous.viewport == value.viewport, previous.history == value.history,
      previous.historyIndex == value.historyIndex, previous.loading == value.loading,
      previous.loaded == value.loaded, previous.error == value.error { return }
    lastPublished = value
    changed(value)
  }

  func navigate(_ request: URLRequest, settle: PageReadiness = .complete) async throws {
    guard let scheme = request.url?.scheme?.lowercased(), ["http", "https", "about"].contains(scheme) else {
      throw BrowserRuntimeError.invalidNavigation("Only HTTP and HTTPS navigation is supported")
    }
    stop()
    lastError = nil
    try await wait(for: view.load(request), settle: settle)
  }

  func loadHTML(_ html: String, url: URL) async throws {
    stop()
    lastError = nil
    try await wait(for: view.loadHTMLString(html, baseURL: url))
  }

  func back() async throws { try await wait(for: view.goBack()) }
  func forward() async throws { try await wait(for: view.goForward()) }
  func reload(bypassCache: Bool) async throws {
    lastError = nil
    try await wait(for: bypassCache ? view.reloadFromOrigin() : view.reload())
  }

  private func wait(for navigation: WKNavigation?, settle: PageReadiness = .complete) async throws {
    guard let navigation else { throw BrowserRuntimeError.historyUnavailable }
    let key = ObjectIdentifier(navigation)
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      try await withCheckedThrowingContinuation { continuation in
        if settle == .commit { commitPending[key] = continuation }
        else { pending[key] = continuation }
        deadlines[key] = Task { [weak self] in
          do { try await Task.sleep(for: .seconds(60)) } catch { return }
          guard let self, self.pending[key] != nil || self.commitPending[key] != nil else { return }
          self.finish(key, error: BrowserRuntimeError.timeout("WebKit navigation exceeded 60 seconds"))
          self.finishCommit(key, error: BrowserRuntimeError.timeout("WebKit navigation exceeded 60 seconds"))
          self.view.stopLoading()
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancel(key) }
    }
  }

  private func cancel(_ key: ObjectIdentifier) {
    guard pending[key] != nil || commitPending[key] != nil else { return }
    finish(key, error: CancellationError())
    finishCommit(key, error: CancellationError())
    view.stopLoading()
  }

  private func finish(_ key: ObjectIdentifier, error: Error? = nil) {
    deadlines.removeValue(forKey: key)?.cancel()
    guard let continuation = pending.removeValue(forKey: key) else { return }
    if let error { continuation.resume(throwing: error) }
    else { continuation.resume() }
  }

  private func finishCommit(_ key: ObjectIdentifier, error: Error? = nil) {
    guard commitPending[key] != nil else { return }
    deadlines.removeValue(forKey: key)?.cancel()
    guard let continuation = commitPending.removeValue(forKey: key) else { return }
    if let error { continuation.resume(throwing: error) }
    else { continuation.resume() }
  }

  func stop() {
    view.stopLoading()
    for key in Array(pending.keys) { finish(key, error: CancellationError()) }
    for key in Array(commitPending.keys) { finishCommit(key, error: CancellationError()) }
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
    lastError = nil
    publish()
  }

  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    generation &+= 1
    loaded = true
    publish()
    if let navigation { finishCommit(ObjectIdentifier(navigation)) }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    loaded = true
    lastError = nil
    publish()
    if let navigation {
      finishCommit(ObjectIdentifier(navigation))
      finish(ObjectIdentifier(navigation))
    }
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    failed(navigation, error: error)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    failed(navigation, error: error)
  }

  private func failed(_ navigation: WKNavigation?, error: Error) {
    if (error as NSError).code != NSURLErrorCancelled { lastError = error.localizedDescription }
    publish()
    if let navigation {
      finish(ObjectIdentifier(navigation), error: error)
      finishCommit(ObjectIdentifier(navigation), error: error)
    }
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    loaded = false
    let message = "The webpage process stopped. Reload the page to continue."
    lastError = message
    for key in Array(pending.keys) { finish(key, error: BrowserRuntimeError.invalidState(message)) }
    for key in Array(commitPending.keys) { finishCommit(key, error: BrowserRuntimeError.invalidState(message)) }
    publish()
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
    let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
    guard ["http", "https", "about", "blob", "data"].contains(scheme) else {
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
    if navigationResponse.isForMainFrame {
      statusCode = (navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 0
    }
    decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
  }
}
