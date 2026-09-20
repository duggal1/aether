import AgentProtocol
import BrowserEngine
import EngineRuntime
import Foundation
import Testing

@Test func bookmarksAddListRemoveRoundTrip() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "bookmarks")
  let first = try await engine.runtime.addBookmark(
    contextID: context.id, url: URL(string: "https://example.test/a")!, title: "Alpha")
  #expect(first.url == "https://example.test/a")
  #expect(first.title == "Alpha")
  let updated = try await engine.runtime.addBookmark(
    contextID: context.id, url: URL(string: "https://example.test/a")!, title: "Alpha 2")
  #expect(updated.title == "Alpha 2")
  #expect(updated.createdAt == first.createdAt)
  _ = try await engine.runtime.addBookmark(
    contextID: context.id, url: URL(string: "https://example.test/b")!, title: "")
  #expect(try await engine.runtime.listBookmarks(contextID: context.id).count == 2)
  #expect(
    try await engine.runtime.removeBookmark(
      contextID: context.id, url: URL(string: "https://example.test/a")!) == true)
  #expect(
    try await engine.runtime.removeBookmark(
      contextID: context.id, url: URL(string: "https://example.test/a")!) == false)
  #expect(try await engine.runtime.listBookmarks(contextID: context.id).count == 1)
}

@Test func bookmarksRejectNonWebURLs() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "bookmark-guard")
  for raw in ["ftp://example.test/file", "file:///etc/passwd", "missing-scheme"] {
    let url = try #require(URL(string: raw))
    await #expect(throws: BrowserRuntimeError.self) {
      try await engine.runtime.addBookmark(contextID: context.id, url: url, title: "x")
    }
  }
}

@Test func bookmarksPersistThroughProfileCheckpoint() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "profiled-bookmarks")
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try await engine.runtime.openProfile(contextID: context.id, directory: directory)
  _ = try await engine.runtime.addBookmark(
    contextID: context.id, url: URL(string: "https://example.test/saved")!, title: "Saved")
  try await engine.runtime.checkpoint(contextID: context.id)

  let reopened = NativeBrowserEngine()
  let fresh = await reopened.runtime.createContext(name: "profiled-bookmarks")
  try await reopened.runtime.openProfile(contextID: fresh.id, directory: directory)
  let restored = try await reopened.runtime.listBookmarks(contextID: fresh.id)
  #expect(restored.count == 1)
  #expect(restored.first?.url == "https://example.test/saved")
  #expect(restored.first?.title == "Saved")
}

@Test func corruptProfileFailsWithoutLosingContext() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "corrupt")
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(
    at: directory, withIntermediateDirectories: true)
  try "not a database".write(
    to: directory.appendingPathComponent("state.sqlite"), atomically: true, encoding: .utf8)
  do {
    try await engine.runtime.openProfile(contextID: context.id, directory: directory)
    Issue.record("Corrupt profile unexpectedly opened")
  } catch {
    let pages = try await engine.runtime.listPages(contextID: context.id)
    #expect(pages.isEmpty)
  }
}

@Test func suggestRanksBookmarksBeforeHistory() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "suggest")
  let page = try await engine.runtime.createPage(contextID: context.id)
  _ = try await engine.runtime.loadHTML(
    pageID: page.id, html: "<html><body>history</body></html>",
    url: URL(string: "https://example.test/history-page")!)
  _ = try await engine.runtime.addBookmark(
    contextID: context.id, url: URL(string: "https://example.test/bookmarked")!,
    title: "Example bookmark")
  let suggestions = try await engine.runtime.suggestNavigation(
    contextID: context.id, prefix: "example.test", limit: 8)
  #expect(suggestions.count == 2)
  #expect(suggestions.first?.kind == "bookmark")
  #expect(suggestions.first?.title == "Example bookmark")
  #expect(suggestions.last?.kind == "history")
  let limited = try await engine.runtime.suggestNavigation(
    contextID: context.id, prefix: "example.test", limit: 1)
  #expect(limited.count == 1)
  #expect(limited.first?.kind == "bookmark")
  #expect(
    try await engine.runtime.suggestNavigation(
      contextID: context.id, prefix: "no-such-host", limit: 8
    ).isEmpty)
}

@Test func searchProviderPersistsPerProfile() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "provider")
  let initial = try await engine.runtime.searchProvider(contextID: context.id)
  #expect(initial.endpoint.absoluteString == "https://www.google.com/search")
  #expect(initial.queryParameter == "q")
  do {
    _ = try await engine.runtime.setSearchProvider(
      contextID: context.id, endpoint: URL(string: "https://search.example.test/find")!,
      queryParameter: "query")
    Issue.record("Provider unexpectedly persisted without a profile")
  } catch BrowserRuntimeError.profileNotConfigured {
  }
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try await engine.runtime.openProfile(contextID: context.id, directory: directory)
  let stored = try await engine.runtime.setSearchProvider(
    contextID: context.id, endpoint: URL(string: "https://search.example.test/find")!,
    queryParameter: "query")
  #expect(stored.queryParameter == "query")
  #expect(try await engine.runtime.searchProvider(contextID: context.id).endpoint.absoluteString
    == "https://search.example.test/find")
  let resolution = try NavigationInputResolver.resolve(
    "engine services", provider: stored)
  #expect(resolution.kind == .search)
  #expect(resolution.url.absoluteString.contains("search.example.test"))
}

@Test func searchProviderRejectsUnsafeEndpoints() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "provider-guard")
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try await engine.runtime.openProfile(contextID: context.id, directory: directory)
  for endpoint in ["ftp://example.test/search", "https://user:pass@example.test/"] {
    do {
      _ = try await engine.runtime.setSearchProvider(
        contextID: context.id, endpoint: URL(string: endpoint)!)
      Issue.record("Unsafe provider unexpectedly accepted: \(endpoint)")
    } catch {
    }
  }
}

@Test func bookmarkAndSuggestDispatcherSurface() async throws {
  let dispatcher = AgentCommandDispatcher(engine: NativeBrowserEngine())
  let context = await dispatcher.handle(AgentRequest(method: .contextCreate))
  let contextID = try #require(context.result?.object?["id"]?.number)
  let added = await dispatcher.handle(AgentRequest(
    method: .contextBookmarkAdd,
    params: [
      "context": .number(contextID), "url": .string("https://example.test/wired"),
      "title": .string("Wired"),
    ]))
  #expect(added.error == nil)
  #expect(added.result?.object?["url"]?.string == "https://example.test/wired")
  let listed = await dispatcher.handle(AgentRequest(
    method: .contextBookmarks, params: ["context": .number(contextID)]))
  #expect(listed.result?.array?.count == 1)
  let suggested = await dispatcher.handle(AgentRequest(
    method: .contextSuggest,
    params: ["context": .number(contextID), "prefix": .string("wired")]))
  #expect(suggested.result?.array?.first?.object?["kind"]?.string == "bookmark")
  let provider = await dispatcher.handle(AgentRequest(
    method: .contextSearchProvider, params: ["context": .number(contextID)]))
  #expect(provider.result?.object?["endpoint"]?.string == "https://www.google.com/search")
  for bad in [
    AgentRequest(
      method: .contextBookmarkAdd,
      params: ["context": .number(contextID), "url": .string("missing-scheme")]),
    AgentRequest(
      method: .contextSuggest, params: ["context": .number(contextID)]),
    AgentRequest(
      method: .contextSuggest,
      params: ["context": .number(contextID), "prefix": .string("x"), "limit": .number(51)]),
    AgentRequest(
      method: .contextSetSearchProvider,
      params: ["context": .number(contextID), "endpoint": .string("gopher://x/")]),
  ] {
    #expect((await dispatcher.handle(bad)).error != nil)
  }
  let removed = await dispatcher.handle(AgentRequest(
    method: .contextBookmarkRemove,
    params: ["context": .number(contextID), "url": .string("https://example.test/wired")]))
  #expect(removed.result?.object?["removed"]?.bool == true)
}
