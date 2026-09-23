import AetherHumanUI
import AppKit
import BrowserEngine
import EngineCore
import EngineRuntime
import Foundation

@MainActor
final class AetherEngineAdapter: BrowserEnginePort, BrowserPageObserving {
  let engine: NativeBrowserEngine
  let profileDirectory: URL
  var restoredProfiles: Set<UUID> = []
  var contexts: [UUID: ContextID] = [:]
  var contextTasks: [UUID: Task<ContextID, Error>] = [:]
  var pages: [String: PageID] = [:]
  var findPositions: [String: (query: String, index: Int)] = [:]
  var surfaces: [String: NSView] = [:]
  var observers: [UUID: AsyncStream<EnginePageSnapshot>.Continuation] = [:]
  private var observation: Task<Void, Never>?
  private var pendingCheckpoints: [ContextID: Task<Void, Never>] = [:]
  var automation: AppAutomationHost?
  var routeStatus: [UUID: NetworkRouteStatus] = [:]
  var observedExitIPs: [UUID: String] = [:]
  var isConnected: Bool { true }

  init(engine: NativeBrowserEngine = NativeBrowserEngine(), profileDirectory: URL? = nil) {
    self.engine = engine
    self.profileDirectory = profileDirectory ?? FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Aether/Profiles", isDirectory: true)
    observation = Task { [weak self, engine] in
      let stream = await engine.runtime.observePages()
      for await state in stream {
        guard !Task.isCancelled, let self else { break }
        let snapshot = self.project(state)
        for observer in self.observers.values { observer.yield(snapshot) }
      }
    }
  }

  func context(for profileID: UUID) async throws -> ContextID {
    if let existing = contexts[profileID] { return existing }
    if let pending = contextTasks[profileID] { return try await pending.value }
    let directory = profileDirectory.appendingPathComponent(profileID.uuidString, isDirectory: true)
    let task = Task { [engine] in
      let context = await engine.createContext(name: profileID.uuidString)
      do {
        try await engine.runtime.openProfile(contextID: context.id, directory: directory)
        return context.id
      } catch {
        try? await engine.destroyContext(context.id)
        throw error
      }
    }
    contextTasks[profileID] = task
    do {
      let id = try await task.value
      contexts[profileID] = id
      contextTasks[profileID] = nil
      return id
    } catch {
      contextTasks[profileID] = nil
      throw error
    }
  }

  func page(_ id: String) throws -> PageID {
    guard let page = pages[id] else { throw BrowserPortError.pageUnavailable }
    return page
  }

  func createPage(profileID: UUID) async throws -> String {
    let context = try await context(for: profileID)
    let page = try await engine.createPage(contextID: context)
    let id = page.id.description
    pages[id] = page.id
    surfaces[id] = try await engine.runtime.webSurface(pageID: page.id)
    return id
  }

  func snapshot(pageID: String) async throws -> EnginePageSnapshot {
    project(try await engine.runtime.pageState(pageID: page(pageID)))
  }

  func project(_ state: RuntimePageState) -> EnginePageSnapshot {
    let url = state.target ?? state.page.url
    return EnginePageSnapshot(id: state.page.id.description, url: url?.absoluteString,
      title: state.page.title, canGoBack: state.page.canGoBack,
      canGoForward: state.page.canGoForward, isLoading: state.loading, progress: state.progress,
      isSecure: url?.scheme == "https", error: state.error, closed: state.closed)
  }

  func navigate(pageID: String, url: URL) async throws {
    _ = try await engine.navigate(pageID: page(pageID), url: url, settle: .commit)
    try await persist(pageID)
  }
  func goBack(pageID: String) async throws {
    _ = try await engine.back(pageID: page(pageID)); try await persist(pageID)
  }
  func goForward(pageID: String) async throws {
    _ = try await engine.forward(pageID: page(pageID)); try await persist(pageID)
  }
  func reload(pageID: String) async throws {
    _ = try await engine.reload(pageID: page(pageID)); try await persist(pageID)
  }
  func stop(pageID: String) async throws {
    await engine.runtime.stopNavigation(pageID: try page(pageID))
  }
  func close(pageID: String) async {
    guard let id = pages.removeValue(forKey: pageID) else { return }
    surfaces.removeValue(forKey: pageID)?.removeFromSuperview()
    let context = try? await engine.runtime.pageInfo(id).contextID
    try? await engine.closePage(id)
    if let context { try? await engine.runtime.checkpoint(contextID: context) }
  }
  func persist(_ id: String) async throws {
    let info = try await engine.runtime.pageInfo(page(id))
    let context = info.contextID
    pendingCheckpoints[context]?.cancel()
    pendingCheckpoints[context] = Task { [weak self, engine] in
      do {
        try await Task.sleep(for: .milliseconds(750))
        try Task.checkCancellation()
        try await engine.runtime.checkpoint(contextID: context)
      } catch is CancellationError { }
      catch {
        FileHandle.standardError.write(Data("Profile checkpoint: \(error)\n".utf8))
      }
      if !Task.isCancelled { self?.pendingCheckpoints[context] = nil }
    }
  }
  func surface(pageID: String) -> NSView? { surfaces[pageID] }

  func pageUpdates() -> AsyncStream<EnginePageSnapshot> {
    let token = UUID()
    let pair = AsyncStream<EnginePageSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(256))
    observers[token] = pair.continuation
    pair.continuation.onTermination = { [weak self] _ in
      Task { @MainActor in self?.observers[token] = nil }
    }
    return pair.stream
  }

  func updatePrivacy(profileID: UUID, policy: BrowserPrivacyPolicy) async throws {
    let context = try await context(for: profileID)
    let rules = AggressiveBlockFilter.ruleList(blockAds: policy.blockAds,
      blockTrackers: policy.blockTrackers, hideIP: policy.hideIP,
      cookieBanners: policy.handleCookieBanners)
    try await engine.runtime.configureContentBlocking(contextID: context,
      rules: rules, enabled: policy.blockAds || policy.blockTrackers || policy.hideIP)
    if policy.handleCookieBanners {
      throw BrowserPortError.unsupported("cookie-banner handling; network filters were applied")
    }
  }

  func setProfileEphemeral(profileID: UUID, enabled: Bool) async throws {
    if enabled {
      let context = try await context(for: profileID)
      try await engine.runtime.setContextEphemeral(contextID: context, enabled: true)
    } else {
      guard let context = contexts[profileID] else { return }
      try await engine.runtime.setContextEphemeral(contextID: context, enabled: false)
    }
  }

  func shutdown() async {
    observation?.cancel()
    for task in pendingCheckpoints.values { task.cancel() }
    pendingCheckpoints.removeAll()
    for id in contexts.values { try? await engine.runtime.checkpoint(contextID: id) }
  }
}
