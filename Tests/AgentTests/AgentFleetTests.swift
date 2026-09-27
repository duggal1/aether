import AgentProtocol
import BrowserEvents
import BrowserEngine
import DOM
import EngineCore
import EngineRuntime
import Foundation
import Testing

private let fleetFixtureURL = URL(string: "https://example.test/")!

private let fleetFixtureHTML = """
  <html><head><title>Fleet</title><style>body{min-height:1200px}</style></head><body>
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
  // `loadHTML` uses WebKit's loadHTMLString and creates no HTTP response.
  #expect(log.isEmpty)
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

@Test func agentClickPublishesViewportTargetAndRealClickState() async throws {
  let (engine, loaded) = try await fleetPage()
  let button = try #require(try await engine.runtime.query(pageID: loaded.id, selector: "#btn"))
  _ = try await engine.runtime.evaluate(pageID: loaded.id,
    source: "document.querySelector('#btn').style.background = '#111'; document.querySelector('#btn').addEventListener('click', () => document.body.dataset.clicked = 'yes'); 'installed'")
  let stream = await engine.runtime.observeAgentInteractions()
  var updates = stream.makeAsyncIterator()
  _ = try await engine.runtime.click(pageID: loaded.id, nodeID: button.id)
  let movement = await updates.next()
  let click = await updates.next()
  #expect(movement?.kind == .move)
  #expect(movement?.point?.x.isFinite == true)
  #expect(movement?.point?.y.isFinite == true)
  #expect(click?.kind == .click)
  #expect(click?.point == movement?.point)
  #expect((click?.targetLuminance ?? 1) < 0.15)
  #expect(try await engine.runtime.evaluate(pageID: loaded.id,
    source: "document.body.dataset.clicked") .value == "yes")
}

@Test func agentTypingPublishesFieldPositionWithoutReplacingPageValue() async throws {
  let (engine, loaded) = try await fleetPage()
  let input = try #require(try await engine.runtime.query(pageID: loaded.id, selector: "#name"))
  let stream = await engine.runtime.observeAgentInteractions()
  var updates = stream.makeAsyncIterator()
  try await engine.runtime.type(pageID: loaded.id, nodeID: input.id, text: "native value")
  let movement = await updates.next()
  let typing = await updates.next()
  #expect(movement?.kind == .move)
  #expect(typing?.kind == .typing)
  #expect(try await engine.runtime.query(pageID: loaded.id, selector: "#name")?.value == "native value")
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
  _ = try await engine.runtime.evaluate(
    pageID: loaded.id, source: "document.querySelector('#bio').setSelectionRange(2, 2)")
  var textareaValue = ""
  do {
    textareaValue = try await engine.runtime.pressKey(pageID: loaded.id, key: "Enter")
  } catch {
    Issue.record("Pressing Enter in a focused textarea failed: \(error)")
  }
  #expect(textareaValue == "hi\n")
  let select = try #require(
    try await engine.runtime.query(pageID: loaded.id, selector: "#color"))
  try await engine.runtime.selectOption(pageID: loaded.id, selectNodeID: select.id, value: "g")
  #expect(try await engine.runtime.query(pageID: loaded.id, selector: "#color")?.value == "g")
  #expect(try await engine.runtime.query(pageID: loaded.id, selector: "option:checked")?.name == "Green")
  await #expect(throws: BrowserRuntimeError.self) {
    try await engine.runtime.selectOption(pageID: loaded.id, selectNodeID: select.id, value: "zzz")
  }
  await #expect(throws: BrowserRuntimeError.self) {
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
  await #expect(throws: BrowserRuntimeError.self) {
    try await engine.runtime.resolveDialog(id: DialogID(rawValue: 999), accept: true)
  }
}

@Test func contextCookiesStoragePermissions() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "data")
  let page = try await engine.runtime.createPage(contextID: context.id)
  _ = try await engine.runtime.loadHTML(
    pageID: page.id, html: "<title>data</title>",
    url: URL(string: "https://example.test/")!)
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
  await #expect(throws: BrowserRuntimeError.self) {
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
  await #expect(throws: BrowserRuntimeError.self) { try await engine.runtime.deleteSession(session.id) }
}

@Test func downloadsRejectDisallowedSchemes() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "dl")
  await #expect(throws: BrowserRuntimeError.self) {
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

@Test func agentFleetWorkspaceLeaseLifecycleAndIsolation() async throws {
  let engine = NativeBrowserEngine()
  let firstContext = await engine.runtime.createContext(name: "worker-a")
  let secondContext = await engine.runtime.createContext(name: "worker-b")
  let firstProfile = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let secondProfile = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try await engine.runtime.openProfile(contextID: firstContext.id, directory: firstProfile)
  try await engine.runtime.openProfile(contextID: secondContext.id, directory: secondProfile)
  let events = await engine.runtime.observeEvents(filter: .family(.lease))
  var iterator = events.makeAsyncIterator()

  let lease = try await engine.runtime.acquireWorkspaceLease(
    contextID: firstContext.id, agentID: "worker-a", durationSeconds: 30,
    repositoryRoot: "/tmp/aether-repo", worktreePath: "/tmp/aether-repo/.worktrees/worker-a")
  #expect(lease.state == .active)
  #expect(lease.repositoryRoot == "/tmp/aether-repo")
  #expect(lease.workspaceID != UUID())
  #expect(await iterator.next()?.name == "lease.acquired")

  await #expect(throws: BrowserRuntimeError.self) {
    try await engine.runtime.acquireWorkspaceLease(
      contextID: firstContext.id, agentID: "worker-b", durationSeconds: 30)
  }

  let renewed = try await engine.runtime.renewWorkspaceLease(
    contextID: firstContext.id, leaseID: lease.leaseID, agentID: "worker-a",
    durationSeconds: 60)
  #expect(renewed.expiresAt > lease.expiresAt)
  #expect(await iterator.next()?.name == "lease.renewed")

  let released = try await engine.runtime.releaseWorkspaceLease(
    contextID: firstContext.id, leaseID: lease.leaseID, agentID: "worker-a")
  #expect(released.state == .released)
  #expect(await iterator.next()?.name == "lease.released")

  let next = try await engine.runtime.acquireWorkspaceLease(
    contextID: firstContext.id, agentID: "worker-b", durationSeconds: 30)
  let other = try await engine.runtime.acquireWorkspaceLease(
    contextID: secondContext.id, agentID: "worker-b", durationSeconds: 30)
  #expect(next.workspaceID == lease.workspaceID)
  #expect(other.workspaceID != next.workspaceID)
  #expect(await engine.runtime.listWorkspaceLeases(contextID: secondContext.id).count == 1)

  _ = try await engine.runtime.cancelWorkspaceLease(
    contextID: firstContext.id, leaseID: next.leaseID)
  _ = try await engine.runtime.releaseWorkspaceLease(
    contextID: secondContext.id, leaseID: other.leaseID, agentID: "worker-b")
  try await engine.runtime.destroyContext(firstContext.id)
  try await engine.runtime.destroyContext(secondContext.id)
  try? FileManager.default.removeItem(at: firstProfile)
  try? FileManager.default.removeItem(at: secondProfile)
}

@Test func agentFleetWorkspaceLeaseReacquisitionAfterGracefulDestroy() async throws {
  let profile = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let firstRuntime = BrowserRuntime()
  let firstContext = await firstRuntime.createContext(name: "recover")
  try await firstRuntime.openProfile(contextID: firstContext.id, directory: profile)
  let original = try await firstRuntime.acquireWorkspaceLease(
    contextID: firstContext.id, agentID: "stable-worker", durationSeconds: 30,
    branchID: UUID().uuidString)
  try await firstRuntime.destroyContext(firstContext.id)

  let restartedRuntime = BrowserRuntime()
  let restoredContext = await restartedRuntime.createContext(name: "recover")
  try await restartedRuntime.openProfile(contextID: restoredContext.id, directory: profile)
  let recovered = await restartedRuntime.workspaceLease(contextID: restoredContext.id)
  // Graceful context destruction persists a release. Crash recovery is covered by
  // WorkspaceLeaseTests, which reopens an active persisted record without destroying it.
  #expect(recovered?.state == .released)
  #expect(recovered?.contextID == restoredContext.id)
  // ContextID is a process-local counter and can have the same raw value in both runtimes.

  let resumed = try await restartedRuntime.acquireWorkspaceLease(
    contextID: restoredContext.id, agentID: "stable-worker", durationSeconds: 30)
  #expect(resumed.workspaceID == original.workspaceID)
  #expect(resumed.leaseID != original.leaseID)
  _ = try await restartedRuntime.releaseWorkspaceLease(
    contextID: restoredContext.id, leaseID: resumed.leaseID, agentID: "stable-worker")
  try await restartedRuntime.destroyContext(restoredContext.id)
  try? FileManager.default.removeItem(at: profile)
}
