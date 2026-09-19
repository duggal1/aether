import AgentProtocol
import BrowserEngine
import EngineRuntime
import Foundation
import Testing

@Test func navigationInputDistinguishesWebURLsAndSearches() throws {
  let host = try NavigationInputResolver.resolve("  example.com/articles?q=1  ")
  #expect(host.kind == .url)
  #expect(host.url.absoluteString == "https://example.com/articles?q=1")

  let local = try NavigationInputResolver.resolve("localhost:8765/fixture")
  #expect(local.kind == .url)
  #expect(local.url.absoluteString == "http://localhost:8765/fixture")

  let loopback = try NavigationInputResolver.resolve("127.0.0.1:8765/")
  #expect(loopback.url.scheme == "http")

  let explicit = try NavigationInputResolver.resolve("http://example.com/")
  #expect(explicit.kind == .url)
  #expect(explicit.url.scheme == "http")

  let search = try NavigationInputResolver.resolve("Swift actors and DOM")
  #expect(search.kind == .search)
  let parts = try #require(URLComponents(url: search.url, resolvingAgainstBaseURL: false))
  #expect(parts.queryItems?.first(where: { $0.name == "q" })?.value == "Swift actors and DOM")
}

@Test func navigationInputProviderEncodesTermsWithoutInjectingParameters() throws {
  let provider = SearchProvider(
    endpoint: URL(string: "https://search.example.test/find?lang=en&q=old")!,
    queryParameter: "q")
  let resolution = try NavigationInputResolver.resolve("a&admin=true #tag", provider: provider)
  #expect(resolution.kind == .search)
  let parts = try #require(URLComponents(url: resolution.url, resolvingAgainstBaseURL: false))
  #expect(parts.queryItems?.count == 2)
  #expect(parts.queryItems?.first(where: { $0.name == "lang" })?.value == "en")
  #expect(parts.queryItems?.first(where: { $0.name == "q" })?.value == "a&admin=true #tag")
  #expect(parts.queryItems?.contains(where: { $0.name == "admin" }) == false)
}

@Test func navigationInputRejectsInvalidSchemesAndProviders() throws {
  #expect(throws: NavigationInputError.self) {
    try NavigationInputResolver.resolve("file:///etc/passwd")
  }
  #expect(throws: NavigationInputError.self) {
    try NavigationInputResolver.resolve("javascript:alert(1)")
  }
  #expect(throws: NavigationInputError.self) {
    try NavigationInputResolver.resolve("  ")
  }
  #expect(throws: NavigationInputError.self) {
    try NavigationInputResolver.resolve("https://person:secret@example.com/")
  }
  let invalid = SearchProvider(endpoint: URL(string: "file:///tmp/search")!)
  #expect(throws: NavigationInputError.self) {
    try NavigationInputResolver.resolve("two words", provider: invalid)
  }
}

@Test func navigationInputDispatcherDeniesUnsafeNavigation() async throws {
  let dispatcher = AgentCommandDispatcher(engine: NativeBrowserEngine())
  let created = await dispatcher.handle(AgentRequest(id: "c", method: .contextCreate))
  let context = try #require(created.result?.object?["id"]?.number)
  let newPage = await dispatcher.handle(AgentRequest(
    id: "p", method: .pageCreate, params: ["context": .number(context)]))
  let page = try #require(newPage.result?.object?["id"]?.number)
  let denied = await dispatcher.handle(AgentRequest(
    id: "deny", method: .pageNavigateInput,
    params: ["page": .number(page), "input": .string("file:///etc/passwd")]))
  #expect(denied.error != nil)
  let listed = await dispatcher.handle(AgentRequest(
    id: "pages", method: .pageList, params: ["context": .number(context)]))
  #expect(listed.result?.array?.count == 1)
  #expect(listed.result?.array?.first?.object?["loaded"]?.bool == false)
}
