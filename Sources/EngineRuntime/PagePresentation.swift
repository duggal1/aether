import Display
import DOM
import EngineCore
import Foundation
import JavaScript

public struct RuntimePageState: Equatable, Sendable {
  public let page: BrowserPageInfo
  public let navigation: NavigationID?
  public let revision: UInt64
  public let scroll: Point
  public let loading: Bool
  public let target: URL?
  public let error: String?
  public let closed: Bool
}

public struct RuntimePageFrame: Sendable {
  public let displayList: DisplayList
  public let viewport: Size
  public let scroll: Point
  public let navigation: NavigationID
  public let revision: UInt64
}

extension BrowserRuntime {
  public func observePages() -> AsyncStream<RuntimePageState> {
    let token = UUID()
    let pair = AsyncStream<RuntimePageState>.makeStream(bufferingPolicy: .bufferingNewest(256))
    pageObservers[token] = pair.continuation
    for context in contexts.values {
      for page in context.pages.values { pair.continuation.yield(state(for: page)) }
    }
    pair.continuation.onTermination = { [weak self] _ in
      Task { await self?.removePageObserver(token) }
    }
    return pair.stream
  }

  func removePageObserver(_ token: UUID) { pageObservers[token] = nil }

  public func pageState(pageID: PageID) throws -> RuntimePageState {
    state(for: try requirePage(pageID))
  }

  func state(for page: PageRecord, closed: Bool = false) -> RuntimePageState {
    if let state = webStates[page.id] {
      return RuntimePageState(page: info(for: page), navigation: nil, revision: state.sequence,
        scroll: page.scroll, loading: state.loading, target: state.url, error: state.error, closed: closed)
    }
    return RuntimePageState(page: info(for: page), navigation: page.loaded?.navigationID,
      revision: page.loaded?.document.mutationVersion ?? 0, scroll: page.scroll,
      loading: navigationLoads[page.id] != nil, target: navigationTargets[page.id],
      error: navigationErrors[page.id], closed: closed)
  }

  func publishPageStates() {
    var current: [PageID: RuntimePageState] = [:]
    for context in contexts.values {
      for page in context.pages.values {
        let value = state(for: page)
        current[page.id] = value
        if observedStates[page.id] != value {
          for observer in pageObservers.values { observer.yield(value) }
        }
      }
    }
    for (id, previous) in observedStates where current[id] == nil {
      let closed = RuntimePageState(page: previous.page, navigation: previous.navigation,
        revision: previous.revision, scroll: previous.scroll, loading: false,
        target: nil, error: nil, closed: true)
      for observer in pageObservers.values { observer.yield(closed) }
    }
    observedStates = current
  }

  public func stopNavigation(pageID: PageID) async {
    if let page = webPages[pageID] { await page.stop() }
    navigationEpochs[pageID] = nil
    navigationLoads.removeValue(forKey: pageID)?.cancel()
    navigationTargets[pageID] = nil
    publishPageStates()
  }

  public func presentationFrame(pageID: PageID) async throws -> RuntimePageFrame {
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    let before = loaded.document.mutationVersion
    page.javascript?.drainCompletions()
    page.javascript?.pumpTimers()
    page.javascript?.drainMicrotasks()
    if before != loaded.document.mutationVersion { try refreshPage(pageID) }
    if let pending = page.pendingAction?.take() {
      if let target = pending.navigation { _ = try await navigate(pageID: pageID, to: target) }
      else if let form = pending.submit { _ = try await submitForm(pageID: pageID, formNodeID: form) }
    }
    let current = try requirePage(pageID)
    guard let document = current.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    publishPageStates()
    return RuntimePageFrame(displayList: document.displayList, viewport: current.viewport,
      scroll: current.scroll, navigation: document.navigationID,
      revision: document.document.mutationVersion)
  }

  public func scrollBy(pageID: PageID, x: Double, y: Double) async throws {
    let offset = try await scrollOffset(pageID: pageID)
    _ = try await scrollTo(pageID: pageID, x: offset.x + x, y: offset.y + y)
    return
    let page = try requirePage(pageID)
    guard let loaded = page.loaded else { throw BrowserRuntimeError.pageNotLoaded(pageID) }
    _ = try await scrollTo(pageID: pageID,
      x: min(max(0, page.scroll.x + x), max(0, loaded.layout.contentSize.width - page.viewport.width)),
      y: min(max(0, page.scroll.y + y), max(0, loaded.layout.contentSize.height - page.viewport.height)))
  }

  public func focusNext(pageID: PageID, backwards: Bool = false) async throws {
    let snapshot = try await snapshot(pageID: pageID)
    let nodes = snapshot.nodes.filter {
      $0.visible && $0.enabled && ($0.editable || ["button", "link", "checkbox", "radio", "combobox"].contains($0.role ?? ""))
    }
    guard !nodes.isEmpty else { return }
    let focused = try await focusedNode(pageID: pageID)?.id
    let old = nodes.firstIndex { $0.id == focused } ?? (backwards ? 0 : -1)
    let index = (old + (backwards ? -1 : 1) + nodes.count) % nodes.count
    _ = try await focus(pageID: pageID, nodeID: nodes[index].id)
    _ = try await scrollIntoView(pageID: pageID, nodeID: nodes[index].id)
  }
}
