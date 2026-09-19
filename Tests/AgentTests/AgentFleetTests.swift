import AgentProtocol
import BrowserEngine
import DOM
import EngineCore
import EngineRuntime
import Foundation
import Testing

private let fleetFixtureURL = URL(string: "https://example.test/")!

private let fleetFixtureHTML = """
  <html><head><title>Fleet</title></head><body>
  <form id="f" action="/q" method="get"><input id="name" name="q" value=""><input type="submit" value="Go"></form>
  <textarea id="bio">hi</textarea>
  <select id="color"><option value="r">Red</option><option value="g">Green</option></select>
  <a href="/x" id="link">X</a><button id="btn">B</button>
  </body></html>
  """

private func fleetPage() async throws -> (NativeBrowserEngine, BrowserPageInfo) {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "fleet")
  let page = try await engine.runtime.createPage(contextID: context.id)
  let loaded = try await engine.runtime.loadHTML(
    pageID: page.id, html: fleetFixtureHTML, url: fleetFixtureURL)
  return (engine, loaded)
}

@Test func loadHTMLBuildsInspectableDocument() async throws {
  let (engine, loaded) = try await fleetPage()
  #expect(loaded.title == "Fleet")
  #expect(loaded.url?.absoluteString == fleetFixtureURL.absoluteString)
  let node = try await engine.runtime.query(pageID: loaded.id, selector: "#name")
  #expect(node?.editable == true)
  let log = try await engine.runtime.networkLogEntries(pageID: loaded.id)
  #expect(log.count == 1)
  #expect(log.first?.statusCode == 200)
  let history = try await engine.runtime.historyEntries(pageID: loaded.id)
  #expect(history.count == 1)
  #expect(history.first?.current == true)
}

@Test func hoverFocusBlurRoundtrip() async throws {
  let (engine, loaded) = try await fleetPage()
  let input = try #require(try await engine.runtime.query(pageID: loaded.id, selector: "#name"))
  let hovered = try await engine.runtime.hover(pageID: loaded.id, nodeID: input.id)
  #expect(hovered?.id == input.id)
  #expect(try await engine.runtime.hoveredNode(pageID: loaded.id)?.id == input.id)
  _ = try await engine.runtime.focus(pageID: loaded.id, nodeID: input.id)
  #expect(try await engine.runtime.focusedNode(pageID: loaded.id)?.id == input.id)
  _ = try await engine.runtime.blur(pageID: loaded.id)
  #expect(try await engine.runtime.focusedNode(pageID: loaded.id) == nil)
}

@Test func scrollAndHitTesting() async throws {
  let (engine, loaded) = try await fleetPage()
  let offset = try await engine.runtime.scrollTo(pageID: loaded.id, x: 0, y: 40)
  #expect(offset.y == 40)
  #expect(try await engine.runtime.scrollOffset(pageID: loaded.id).y == 40)
  let input = try #require(try await engine.runtime.query(pageID: loaded.id, selector: "#name"))
  let intoView = try await engine.runtime.scrollIntoView(pageID: loaded.id, nodeID: input.id)
  #expect(intoView.x >= 0)
  #expect(intoView.y >= 0)
  _ = try await engine.runtime.nodeAtPoint(pageID: loaded.id, x: 4, y: 4)
}

@Test func keyboardFillSelect() async throws {
  let (engine, loaded) = try await fleetPage()
  let input = try #require(try await engine.runtime.query(pageID: loaded.id, selector: "#name"))
  _ = try await engine.runtime.focus(pageID: loaded.id, nodeID: input.id)
  #expect(try await engine.runtime.pressKey(pageID: loaded.id, key: "a") == "a")
  #expect(try await engine.runtime.pressKey(pageID: loaded.id, key: "b") == "ab")
  #expect(try await engine.runtime.pressKey(pageID: loaded.id, key: "Backspace") == "a")
  try await engine.runtime.fill(pageID: loaded.id, nodeID: input.id, value: "hello")
  #expect(try await engine.runtime.query(pageID: loaded.id, selector: "#name")?.value == "hello")
  let area = try #require(try await engine.runtime.query(pageID: loaded.id, selector: "#bio"))
  _ = try await engine.runtime.focus(pageID: loaded.id, nodeID: area.id)
  #expect(try await engine.runtime.pressKey(pageID: loaded.id, key: "Enter") == "hi\n")
  let select = try #require(
    try await engine.runtime.query(pageID: loaded.id, selector: "#color"))
  try await engine.runtime.selectOption(pageID: loaded.id, selectNodeID: select.id, value: "g")
  #expect(
    try await engine.runtime.query(pageID: loaded.id, selector: "option[selected]")?.name
      == "Green")
  await await #expect(throws: BrowserRuntimeError.self) {
    try await engine.runtime.selectOption(pageID: loaded.id, selectNodeID: select.id, value: "zzz")
  }
  await await #expect(throws: BrowserRuntimeError.self) {
    try await engine.runtime.submitForm(pageID: loaded.id, formNodeID: input.id)
  }
}

@Test func consoleFrameWorkersDialogs() async throws {
  let (engine, loaded) = try await fleetPage()
  _ = try await engine.runtime.evaluate(pageID: loaded.id, source: "console.log('hi there')")
  #expect(try await engine.runtime.consoleOutput(pageID: loaded.id) == ["hi there"])
  #expect(try await engine.runtime.mainFrame(pageID: loaded.id).title == "Fleet")
  #expect(try await engine.runtime.listWorkers(pageID: loaded.id).isEmpty)
  #expect(try await engine.runtime.pendingDialogs(pageID: loaded.id).isEmpty)
  await await #expect(throws: BrowserRuntimeError.self) {
    try await engine.runtime.resolveDialog(id: DialogID(rawValue: 999), accept: true)
  }
}

@Test func contextCookiesStoragePermissions() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "data")
  try await engine.runtime.setCookie(
    contextID: context.id,
    cookie: CookieInfo(name: "s", value: "1", domain: "example.test", path: "/"))
  #expect(try await engine.runtime.listCookies(contextID: context.id).count == 1)
  try await engine.runtime.removeCookie(
    contextID: context.id, name: "s", domain: "example.test")
  #expect(try await engine.runtime.listCookies(contextID: context.id).isEmpty)
  try await engine.runtime.setCookie(
    contextID: context.id,
    cookie: CookieInfo(name: "a", value: "1", domain: "example.test", path: "/"))
  try await engine.runtime.setCookie(
    contextID: context.id,
    cookie: CookieInfo(name: "b", value: "2", domain: "example.test", path: "/"))
  try await engine.runtime.clearCookies(contextID: context.id)
  #expect(try await engine.runtime.listCookies(contextID: context.id).isEmpty)

  try await engine.runtime.storageSet(
    contextID: context.id, origin: "https://example.test", key: "k", value: "v")
  #expect(
    try await engine.runtime.storageValues(contextID: context.id, origin: "https://example.test")[
      "k"] == "v")
  #expect(try await engine.runtime.storageOrigins(contextID: context.id).count == 1)
  try await engine.runtime.storageRemove(
    contextID: context.id, origin: "https://example.test", key: "k")
  #expect(
    try await engine.runtime.storageValues(contextID: context.id, origin: "https://example.test")
      .isEmpty)
  try await engine.runtime.storageSet(
    contextID: context.id, origin: "https://example.test", key: "k", value: "v")
  try await engine.runtime.storageClear(contextID: context.id, origin: "https://example.test")
  #expect(try await engine.runtime.storageOrigins(contextID: context.id).isEmpty)

  #expect(
    try await engine.runtime.permissionDecision(
      contextID: context.id, permission: "camera", origin: "https://example.test") == "prompt")
  try await engine.runtime.setPermission(
    contextID: context.id, permission: "camera", origin: "https://example.test",
    decision: "allow")
  #expect(
    try await engine.runtime.permissionDecision(
      contextID: context.id, permission: "camera", origin: "https://example.test") == "allow")
  #expect(try await engine.runtime.listPermissions(contextID: context.id).count == 1)
}

@Test func lifecycleSuspendFreezeDiscardRestore() async throws {
  let (engine, loaded) = try await fleetPage()
  _ = try await engine.runtime.setLifecycle(pageID: loaded.id, state: .suspended)
  #expect(try await engine.runtime.lifecycleState(pageID: loaded.id) == .suspended)
  _ = try await engine.runtime.evaluate(pageID: loaded.id, source: "1")
  _ = try await engine.runtime.setLifecycle(pageID: loaded.id, state: .frozen)
  #expect(try await engine.runtime.query(pageID: loaded.id, selector: "#name") != nil)
  _ = try await engine.runtime.setLifecycle(pageID: loaded.id, state: .discarded)
  await await #expect(throws: BrowserRuntimeError.self) {
    try await engine.runtime.query(pageID: loaded.id, selector: "#name")
  }
  _ = try await engine.runtime.restorePage(pageID: loaded.id)
  #expect(try await engine.runtime.query(pageID: loaded.id, selector: "#name") != nil)
  #expect(try await engine.runtime.lifecycleState(pageID: loaded.id) == .active)
}

@Test func fleetSweepDemotesExcessPages() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "sweep")
  let first = try await engine.runtime.createPage(contextID: context.id)
  _ = try await engine.runtime.loadHTML(
    pageID: first.id, html: fleetFixtureHTML, url: fleetFixtureURL)
  let second = try await engine.runtime.createPage(contextID: context.id)
  _ = try await engine.runtime.loadHTML(
    pageID: second.id, html: fleetFixtureHTML, url: fleetFixtureURL)
  let applied = try await engine.runtime.sweepFleet(
    maxActive: 1, memoryBudgetBytes: 1_000_000_000)
  #expect(applied.count == 1)
  let stats = await engine.runtime.fleetStats()
  #expect(stats.totalPages == 2)
  #expect(stats.suspended + stats.frozen + stats.discarded == 1)
  #expect(stats.estimatedBytes > 0)
  #expect(await engine.runtime.fleetPages().count == 2)
}

@Test func sessionsGroupContexts() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "grouped")
  let page = try await engine.runtime.createPage(contextID: context.id)
  _ = try await engine.runtime.loadHTML(
    pageID: page.id, html: fleetFixtureHTML, url: fleetFixtureURL)
  let session = await engine.runtime.createSession(name: "work")
  #expect(await engine.runtime.listSessions().count == 1)
  #expect(try await engine.runtime.sessionPages(session.id).count == 1)
  try await engine.runtime.deleteSession(session.id)
  #expect(await engine.runtime.listSessions().isEmpty)
  await await #expect(throws: BrowserRuntimeError.self) { try await engine.runtime.deleteSession(session.id) }
}

@Test func downloadsRejectDisallowedSchemes() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "dl")
  await await #expect(throws: BrowserRuntimeError.self) {
    try await engine.runtime.startDownload(
      contextID: context.id, url: "ftp://example.test/file.bin", path: nil)
  }
  #expect(try await engine.runtime.listDownloads(contextID: context.id).isEmpty)
}

@Test func dispatcherExposesFleetSurface() async throws {
  let dispatcher = AgentCommandDispatcher(engine: NativeBrowserEngine())
  let created = await dispatcher.handle(
    AgentRequest(id: "c", method: .contextCreate, params: ["name": .string("w")]))
  let context = try #require(created.result?.object?["id"]?.number)
  let page = await dispatcher.handle(
    AgentRequest(
      id: "p", method: .pageCreate,
      params: ["context": .number(context)]))
  #expect(page.error == nil)
  let pageID = try #require(page.result?.object?["id"]?.number)
  let loaded = await dispatcher.handle(
    AgentRequest(
      id: "h", method: .pageLoadHTML,
      params: [
        "page": .number(pageID), "url": .string("https://example.test/"),
        "html": .string("<html><head><title>T</title></head><body></body></html>"),
      ]))
  #expect(loaded.error == nil)
  let frozen = await dispatcher.handle(
    AgentRequest(
      id: "f", method: .pageSetLifecycle,
      params: ["page": .number(pageID), "lifecycle": .string("frozen")]))
  #expect(frozen.error == nil)
  let stats = await dispatcher.handle(AgentRequest(id: "s", method: .fleetStats))
  #expect(stats.error == nil)
  #expect(stats.result?.object?["frozen"]?.number == 1)
  let history = await dispatcher.handle(
    AgentRequest(id: "hh", method: .pageHistory, params: ["page": .number(pageID)]))
  #expect(history.result?.array?.count == 1)
}
