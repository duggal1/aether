import AetherHumanUI
import AppKit
import EngineRuntime
import Foundation
import Testing

@MainActor
private final class StubPageEngine: BrowserEnginePort, BrowserPageObserving {
    private var continuation: AsyncStream<EnginePageSnapshot>.Continuation?
    private var stream: AsyncStream<EnginePageSnapshot>?
    private(set) var navigatedURLs: [String] = []
    private(set) var snapshots: [String: EnginePageSnapshot] = [:]
    var navigateDelay: Duration = .zero
    var navigateError: Error?
    var reloadDelay: Duration = .zero
    var reloadError: Error?
    private var pages = 0

    var isConnected: Bool { true }

    func pageUpdates() -> AsyncStream<EnginePageSnapshot> {
        if let stream { return stream }
        let pair = AsyncStream<EnginePageSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(64))
        continuation = pair.continuation
        stream = pair.stream
        return pair.stream
    }

    func emit(_ snapshot: EnginePageSnapshot) {
        snapshots[snapshot.id] = snapshot
        continuation?.yield(snapshot)
    }

    func createPage(profileID: UUID) async throws -> String {
        pages += 1
        return "page-\(pages)"
    }

    func snapshot(pageID: String) async throws -> EnginePageSnapshot {
        snapshots[pageID] ?? EnginePageSnapshot(id: pageID, url: nil, title: "",
            canGoBack: false, canGoForward: false)
    }

    func navigate(pageID: String, url: URL) async throws {
        navigatedURLs.append(url.absoluteString)
        if navigateDelay > .zero { try await Task.sleep(for: navigateDelay) }
        if let navigateError { throw navigateError }
    }

    func goBack(pageID: String) async throws {}
    func goForward(pageID: String) async throws {}
    func reload(pageID: String) async throws {
        if reloadDelay > .zero { try await Task.sleep(for: reloadDelay) }
        if let reloadError { throw reloadError }
    }
    func stop(pageID: String) async throws {}
    func close(pageID: String) async {}
    func surface(pageID: String) -> NSView? { nil }
    func updatePrivacy(profileID: UUID, policy: BrowserPrivacyPolicy) async throws {}
    func setProfileEphemeral(profileID: UUID, enabled: Bool) async throws {}
}

@MainActor
private func settledState(_ id: String, _ url: String, loading: Bool, contentReady: Bool,
                          progress: Double = 0.6, error: String? = nil) -> EnginePageSnapshot {
    EnginePageSnapshot(id: id, url: url, title: url, canGoBack: false, canGoForward: false,
        isLoading: loading, contentReady: contentReady, progress: progress,
        isSecure: true, error: error, closed: false)
}

@MainActor
private func awaitTab(_ tab: BrowserTab, _ condition: (BrowserTab) -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(4)
    while Date() < deadline {
        if condition(tab) { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition(tab)
}


private func isFailed(_ state: TabLoadState) -> Bool {
    if case .failed = state { return true }
    return false
}

@MainActor
struct NavigationStateTests {
    @Test func interruptedRequestWithoutDocumentClearsLoading() async throws {
        let engine = StubPageEngine()
        let window = BrowserWindowModel(workspace: BrowserWorkspace(engine: engine))
        guard let tab = window.selected else { throw TestFailure.missingTab }
        window.navigate(tab, text: "apple.com")
        #expect(await awaitTab(tab) { $0.enginePageID != nil })
        guard let pageID = tab.enginePageID else { throw TestFailure.missingTab }
        engine.emit(settledState(pageID, "https://apple.com", loading: false, contentReady: false))
        #expect(await awaitTab(tab) { $0.loadState == .newTab })
        #expect(tab.pendingURL == nil)
        #expect(tab.url == nil)
    }

    @Test func committedContentReportsReadyWhileSubresourcesFinish() async throws {
        let engine = StubPageEngine()
        engine.navigateDelay = .milliseconds(300)
        let window = BrowserWindowModel(workspace: BrowserWorkspace(engine: engine))
        guard let tab = window.selected else { throw TestFailure.missingTab }
        window.navigate(tab, text: "apple.com")
        #expect(tab.loadState == .loading)
        #expect(tab.pendingURL == "https://apple.com")
        #expect(await awaitTab(tab) { $0.enginePageID != nil })
        guard let pageID = tab.enginePageID else { throw TestFailure.missingTab }
        engine.emit(settledState(pageID, "https://apple.com", loading: true,
            contentReady: false, progress: 0.4))
        #expect(await awaitTab(tab) { !$0.contentReady && $0.isLoading })
        #expect(tab.loadState == .loading)
        // Commit is visual readiness: the document is on screen, so the tab
        // reports ready even while subresources (ads, analytics) still load.
        // isLoading stays true so the stop control keeps working.
        engine.emit(settledState(pageID, "https://apple.com", loading: true,
            contentReady: true, progress: 0.8))
        #expect(await awaitTab(tab) { $0.contentReady && $0.isLoading })
        #expect(tab.loadState == .ready)
        #expect(tab.isLoading)
        #expect(tab.loadProgress == 0.8)
        #expect(tab.pendingURL == nil)
        engine.emit(settledState(pageID, "https://apple.com", loading: false,
            contentReady: true, progress: 1))
        #expect(await awaitTab(tab) { !$0.isLoading })
        #expect(tab.loadState == .ready)
        #expect(tab.pendingURL == nil)
    }

    @Test func cancelledNavigationNeverBecomesAFailure() async throws {
        let engine = StubPageEngine()
        let window = BrowserWindowModel(workspace: BrowserWorkspace(engine: engine))
        guard let tab = window.selected else { throw TestFailure.missingTab }
        engine.navigateError = CancellationError()
        window.navigate(tab, text: "apple.com")
        try await Task.sleep(for: .milliseconds(250))
        #expect(!isFailed(tab.loadState))
        #expect(tab.loadState == .loading)
        #expect(tab.pendingURL == "https://apple.com")
    }

    @Test func supersededReloadCannotFailTheNewerNavigation() async throws {
        let engine = StubPageEngine()
        let window = BrowserWindowModel(workspace: BrowserWorkspace(engine: engine))
        guard let tab = window.selected else { throw TestFailure.missingTab }
        window.navigate(tab, text: "apple.com")
        #expect(await awaitTab(tab) { $0.enginePageID != nil })
        guard let pageID = tab.enginePageID else { throw TestFailure.missingTab }
        engine.emit(settledState(pageID, "https://apple.com", loading: false, contentReady: true))
        #expect(await awaitTab(tab) { $0.loadState == .ready })
        engine.reloadDelay = .milliseconds(200)
        engine.reloadError = CancellationError()
        window.perform(.reload)
        try await Task.sleep(for: .milliseconds(50))
        window.navigate(tab, text: "fast.example")
        engine.emit(settledState(pageID, "https://fast.example", loading: false, contentReady: true))
        #expect(await awaitTab(tab) { $0.url == "https://fast.example" })
        #expect(await awaitTab(tab) { $0.loadState == .ready })
        try await Task.sleep(for: .milliseconds(500))
        #expect(tab.loadState == .ready)
        #expect(!isFailed(tab.loadState))
    }

    @Test func retryIssuesOneNavigationPerAttempt() async throws {
        let engine = StubPageEngine()
        let window = BrowserWindowModel(workspace: BrowserWorkspace(engine: engine))
        guard let tab = window.selected else { throw TestFailure.missingTab }
        engine.navigateError = BrowserPortError.pageUnavailable
        window.navigate(tab, text: "apple.com")
        #expect(await awaitTab(tab) { isFailed($0.loadState) })
        #expect(tab.pendingURL == "https://apple.com")
        #expect(tab.url == "https://apple.com")
        engine.navigateDelay = .milliseconds(200)
        window.navigate(tab, text: tab.pendingURL ?? "")
        #expect(await awaitTab(tab) { _ in engine.navigatedURLs.count == 2 })
        #expect(engine.navigatedURLs == ["https://apple.com", "https://apple.com"])
        #expect(tab.loadState == .loading)
        #expect(await awaitTab(tab) { isFailed($0.loadState) })
    }

    @Test func lateNavigationErrorCannotReplacePublishedContent() async throws {
        let engine = StubPageEngine()
        engine.navigateDelay = .milliseconds(200)
        engine.navigateError = BrowserPortError.pageUnavailable
        let window = BrowserWindowModel(workspace: BrowserWorkspace(engine: engine))
        guard let tab = window.selected else { throw TestFailure.missingTab }
        window.navigate(tab, text: "apple.com")
        #expect(await awaitTab(tab) { $0.enginePageID != nil })
        guard let pageID = tab.enginePageID else { throw TestFailure.missingTab }
        engine.emit(settledState(pageID, "https://apple.com", loading: false, contentReady: true))
        #expect(await awaitTab(tab) { $0.loadState == .ready })
        try await Task.sleep(for: .milliseconds(300))
        #expect(tab.loadState == .ready)
    }

    enum TestFailure: Error {
        case missingTab
        case neverFailed
    }
}

@Test func uiAndEngineAddressClassificationAgree() throws {
    let corpus = [
        "apple.com", "Apple.Com", "apple.com:8443", "www.apple.com/watch?v=1&x=2#f",
        "https://apple.com", "http://apple.com/a/b?c=d", "youtube.com/watch?v=dQw4w9WgXcQ",
        "localhost", "localhost:3000", "LOCALHOST:3000/api?q=1", "127.0.0.1", "127.0.0.1:8765/",
        "192.168.1.1", "10.0.0.5:8080/status", "[::1]:3000", "2001:db8::1",
        "example.com.", "example.com:8080/a?x=1#f", "sub.domain.example.co.uk/path",
        "hi", "how fast is webkit", "what is the fastest browser", "v1.2", "3.14", "notaurl",
        "two words", "apple pie recipe", "user@example.com", "https://person:secret@example.com/",
        "example.com:abc", "file:///etc/passwd", "javascript:alert(1)", "about:blank",
        "  apple.com  ", "", "not a url .com",
    ]
    for text in corpus {
        let ui = AddressResolver.directURL(text)?.absoluteString
        let engine = engineDirectURL(text)?.absoluteString
        #expect(ui == engine, "classification diverged for “\(text)”: ui=\(ui ?? "nil") engine=\(engine ?? "nil")")
    }
}

private func engineDirectURL(_ text: String) -> URL? {
    guard let resolution = try? NavigationInputResolver.resolve(text) else { return nil }
    return resolution.kind == .url ? resolution.url : nil
}
