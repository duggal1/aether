import EngineCore
import Foundation
import Testing
@testable import EngineRuntime

@Test func webKitPublicationTracksSubscriptionsChangesAndClosure() async throws {
  let runtime = BrowserRuntime()
  try await runtime.checkWebKitPublication()
}

@Test func webKitProgressOnlyUpdatesPreservePageActivity() async throws {
  let runtime = BrowserRuntime()
  try await runtime.checkWebKitProgressUpdates()
}

@Test func webKitPublicationScalesWithChangedPages() async throws {
  let runtime = BrowserRuntime()
  try await runtime.measureWebKitPublication()
}

extension BrowserRuntime {
  private func seedPublicationPages(_ count: Int) -> ContextID {
    let context = createContext(name: "publication-test").id
    for index in 1...count {
      let id = PageID(rawValue: UInt64(index))
      contexts[context]?.pages[id] = PageRecord(id: id, contextID: context,
        viewport: Size(width: 1280, height: 800), history: [], historyIndex: -1,
        lifecycle: .active, scroll: .zero, lastActive: 0, networkLog: [], dialogs: [:])
    }
    return context
  }

  private func publicationState(_ sequence: UInt64, title: String, progress: Double = 1.0) -> WebPageState {
    WebPageState(sequence: sequence, url: URL(string: "https://fixture.test/"), title: title,
      viewport: Size(width: 1280, height: 800), history: [], historyIndex: -1,
      loading: false, loaded: true, contentReady: true, progress: progress, statusCode: 200, error: nil)
  }

  fileprivate func checkWebKitPublication() async throws {
    let context = seedPublicationPages(3)
    let id = PageID(rawValue: 1)
    receiveWebState(publicationState(1, title: "Before subscription"), pageID: id)
    #expect(observedStates.isEmpty)
    #expect(try pageState(pageID: id).page.title == "Before subscription")
    let stream = observePages()
    let tokens = Array(pageObservers.keys)
    #expect(observedStates.count == 3)
    let peer = observedStates[PageID(rawValue: 2)]
    receiveWebState(publicationState(2, title: "After subscription"), pageID: id)
    #expect(observedStates[id]?.page.title == "After subscription")
    #expect(observedStates[PageID(rawValue: 2)] == peer)
    #expect(pageStateUpdate == nil)
    receiveWebState(publicationState(1, title: "Stale"), pageID: id)
    #expect(observedStates[id]?.page.title == "After subscription")
    contexts[context]?.pages.removeValue(forKey: id)
    #expect(observedStates[id] == nil)
    #expect(observedStates.count == 2)
    var iterator = stream.makeAsyncIterator()
    var delivered: [RuntimePageState] = []
    for _ in 0..<5 {
      if let value = await iterator.next() { delivered.append(value) }
    }
    #expect(delivered.count == 5)
    #expect(delivered.suffix(2).first?.page.title == "After subscription")
    #expect(delivered.last?.page.id == id)
    #expect(delivered.last?.closed == true)
    for token in tokens { removePageObserver(token) }
    #expect(observedStates.isEmpty)
    withExtendedLifetime(stream) {}
  }

  fileprivate func checkWebKitProgressUpdates() throws {
    _ = seedPublicationPages(1)
    let id = PageID(rawValue: 1)
    receiveWebState(publicationState(1, title: "Fixture", progress: 0.2), pageID: id)
    let activity = try requirePage(id).lastActive
    let stream = observePages()
    receiveWebState(publicationState(2, title: "Fixture", progress: 0.7), pageID: id)
    #expect(try requirePage(id).lastActive == activity)
    #expect(observedStates[id]?.progress == 0.7)
    receiveWebState(publicationState(1, title: "Stale", progress: 0.1), pageID: id)
    #expect(observedStates[id]?.progress == 0.7)
    for token in Array(pageObservers.keys) { removePageObserver(token) }
    withExtendedLifetime(stream) {}
  }

  fileprivate func measureWebKitPublication() throws {
    let context = seedPublicationPages(512)
    let stream = observePages()
    let id = PageID(rawValue: 1)
    let clock = ContinuousClock()
    let iterations = 1_000
    let fullStart = clock.now
    for index in 1...iterations {
      webStates[id] = publicationState(UInt64(index), title: "Update \(index)")
      var page = try requirePage(id)
      page.lastActive = Double(index)
      contexts[context]?.pages[id] = page
    }
    let full = fullStart.duration(to: clock.now)
    let focusedStart = clock.now
    for index in (iterations + 1)...(iterations * 2) {
      receiveWebState(publicationState(UInt64(index), title: "Update \(index)"), pageID: id)
    }
    let focused = focusedStart.duration(to: clock.now)
    #expect(observedStates.count == 512)
    #expect(observedStates[id]?.page.title == "Update 2000")
    #expect(observedStates[PageID(rawValue: 512)]?.page.title == "")
    func milliseconds(_ duration: Duration) -> Double {
      Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
    print("WEBKIT_PUBLICATION_BENCH pages=512 updates=1000 full_ms=\(milliseconds(full)) focused_ms=\(milliseconds(focused))")
    for token in Array(pageObservers.keys) { removePageObserver(token) }
    withExtendedLifetime(stream) {}
  }
}
