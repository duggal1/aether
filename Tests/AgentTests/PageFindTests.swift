import AgentProtocol
import BrowserEngine
import EngineCore
import EngineRuntime
import Foundation
import Testing

@Test func findInPageReturnsOnlyVisibleTextNodesAndOffsets() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "find")
  let page = try await engine.runtime.createPage(contextID: context.id)
  _ = try await engine.runtime.loadHTML(
    pageID: page.id,
    html: """
      <html><head><title>Needle in title</title><script>var hidden='Needle';</script></head>
      <body><p>Needle needle</p><div style="display:none">Needle</div>
      <p>Needle from another paragraph</p></body></html>
      """,
    url: URL(string: "https://example.test/find")!)
  let snapshot = try await engine.runtime.snapshot(pageID: page.id)
  let matches = PageTextSearch.find(in: snapshot, query: "needle")
  #expect(matches.count == 3)
  #expect(matches.map(\.characterOffset) == [0, 7, 0])
  #expect(matches.map(\.text) == ["Needle", "needle", "Needle"])
  #expect(PageTextSearch.find(in: snapshot, query: "needle", caseSensitive: true).count == 2)
  #expect(PageTextSearch.find(in: snapshot, query: "needle", maximumMatches: 1).count == 1)
  #expect(PageTextSearch.find(in: snapshot, query: "", maximumMatches: 100).isEmpty)
}

@Test func findInPageUsesLiveMutatedDOM() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "find-mutate")
  let page = try await engine.runtime.createPage(contextID: context.id)
  _ = try await engine.runtime.loadHTML(
    pageID: page.id,
    html: "<html><body><p id='live'>Before</p></body></html>",
    url: URL(string: "https://example.test/mutate")!)
  let first = try await engine.runtime.snapshot(pageID: page.id)
  #expect(PageTextSearch.find(in: first, query: "after").isEmpty)
  _ = try await engine.runtime.evaluate(
    pageID: page.id, source: "document.getElementById('live').textContent='After'")
  let later = try await engine.runtime.snapshot(pageID: page.id)
  #expect(later.mutationVersion > first.mutationVersion)
  #expect(PageTextSearch.find(in: later, query: "after").count == 1)
}

@Test func findInPageDispatcherReportsMutationVersionAndDeniesBadLimits() async throws {
  let dispatcher = AgentCommandDispatcher(engine: NativeBrowserEngine())
  let context = await dispatcher.handle(AgentRequest(method: .contextCreate))
  let contextID = try #require(context.result?.object?["id"]?.number)
  let page = await dispatcher.handle(AgentRequest(
    method: .pageCreate, params: ["context": .number(contextID)]))
  let pageID = try #require(page.result?.object?["id"]?.number)
  let loaded = await dispatcher.handle(AgentRequest(
    method: .pageLoadHTML,
    params: [
      "page": .number(pageID),
      "url": .string("https://example.test"),
      "html": .string("<html><body><p>Found found</p></body></html>"),
    ]))
  #expect(loaded.error == nil)
  let result = await dispatcher.handle(AgentRequest(
    method: .pageFind,
    params: ["page": .number(pageID), "query": .string("found"), "limit": .number(1)]))
  #expect(result.error == nil)
  #expect(result.result?.object?["mutationVersion"]?.number != nil)
  #expect(result.result?.object?["matches"]?.array?.count == 1)
  for invalid in [0, -1, 1001, 0.5, 1e100] {
    let denied = await dispatcher.handle(AgentRequest(
      method: .pageFind,
      params: ["page": .number(pageID), "query": .string("found"),
               "limit": .number(invalid)]))
    #expect(denied.error != nil)
  }
}
