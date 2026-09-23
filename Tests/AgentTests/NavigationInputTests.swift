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

@Test func navigationInputRoutesBareAddressesDirectly() throws {
  let apple = try NavigationInputResolver.resolve("apple.com")
  #expect(apple.kind == .url)
  #expect(apple.url.absoluteString == "https://apple.com")

  let secure = try NavigationInputResolver.resolve("https://apple.com")
  #expect(secure.kind == .url)

  let watch = try NavigationInputResolver.resolve("youtube.com/watch?v=dQw4w9WgXcQ")
  #expect(watch.kind == .url)
  #expect(watch.url.absoluteString == "https://youtube.com/watch?v=dQw4w9WgXcQ")

  let port = try NavigationInputResolver.resolve("example.com:8080/a?x=1")
  #expect(port.kind == .url)
  #expect(port.url.absoluteString == "https://example.com:8080/a?x=1")

  let upper = try NavigationInputResolver.resolve("LOCALHOST:3000/api")
  #expect(upper.kind == .url)
  #expect(upper.url.scheme == "http")

  let ipv4 = try NavigationInputResolver.resolve("192.168.1.1/status")
  #expect(ipv4.kind == .url)
  #expect(ipv4.url.scheme == "http")

  let ipv6 = try NavigationInputResolver.resolve("[::1]:3000/")
  #expect(ipv6.kind == .url)
  #expect(ipv6.url.scheme == "http")

  let dotted = try NavigationInputResolver.resolve("apple.com.")
  #expect(dotted.kind == .url)
}

@Test func navigationInputKeepsOrdinaryTextAsSearch() throws {
  for query in ["hi", "how fast is webkit", "v1.2", "3.14", "notaurl"] {
    let resolution = try NavigationInputResolver.resolve(query)
    #expect(resolution.kind == .search, "expected search for \(query)")
  }
  let words = try NavigationInputResolver.resolve("example.com:abc")
  #expect(words.kind == .search)
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
