import AetherCapture
import AgentProtocol
import BrowserEngine
import EngineCore
import EngineRuntime
import Foundation
import Testing

private let captureFixtureURL = URL(string: "https://example.test/capture")!

private let captureFixtureHTML = """
  <html><head><title>Capture Fixture</title><style>body { color: red; }</style></head><body>
  <header id="top"><h1>Headline</h1></header>
  <main><section><p>Hello <a href="/more">more</a></p><img src="https://example.test/i.png" alt="pic"></section>
  <canvas id="c"></canvas>
  <form><input type="password" id="pw" value="secret"></form>
  <div data-aether-redact>classified</div></main>
  </body></html>
  """

private func captureFixturePage() async throws -> (NativeBrowserEngine, BrowserPageInfo) {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "capture-test")
  let page = try await engine.runtime.createPage(
    contextID: context.id, viewport: Size(width: 800, height: 600))
  let loaded = try await engine.runtime.loadHTML(
    pageID: page.id, html: captureFixtureHTML, url: captureFixtureURL)
  return (engine, loaded)
}

@Test func captureSessionIsIsolatedFromHumanPages() async throws {
  let engine = NativeBrowserEngine()
  let human = await engine.runtime.createContext(name: "human")
  let humanPage = try await engine.runtime.createPage(contextID: human.id)
  _ = try await engine.runtime.loadHTML(
    pageID: humanPage.id, html: "<html><head><title>Human</title></head><body></body></html>",
    url: URL(string: "https://example.test/human")!)
  let baseline = await engine.runtime.listContexts().count
  let adapter = BrowserCaptureEngine(runtime: engine.runtime)
  let session = try await adapter.makeCaptureSession(
    viewport: CaptureViewport(width: 800, height: 600, scale: 1))
  #expect(await engine.runtime.listContexts().count == baseline + 1)
  await session.close()
  #expect(await engine.runtime.listContexts().count == baseline)
  #expect(try await engine.runtime.pageInfo(humanPage.id).title == "Human")
}

@Test func captureSessionRejectsUnsupportedViewport() async throws {
  let engine = NativeBrowserEngine()
  let adapter = BrowserCaptureEngine(runtime: engine.runtime)
  let baseline = await engine.runtime.listContexts().count
  #expect(throws: CaptureFailure.self) {
    try await adapter.makeCaptureSession(viewport: CaptureViewport(width: 0, height: 600, scale: 1))
  }
  #expect(throws: CaptureFailure.self) {
    try await adapter.makeCaptureSession(viewport: CaptureViewport(width: 800, height: 600, scale: 2))
  }
  #expect(await engine.runtime.listContexts().count == baseline)
}

@Test func captureStateReportsRealGeometry() async throws {
  let (engine, loaded) = try await captureFixturePage()
  let data = try await engine.runtime.captureState(pageID: loaded.id)
  #expect(data.title == "Capture Fixture")
  #expect(data.url?.absoluteString == captureFixtureURL.absoluteString)
  #expect(data.viewport.width == 800)
  #expect(data.viewport.height == 600)
  #expect(data.documentSize.height > 0)
  #expect(data.scroll.y == 0)
  #expect(data.statusCode == 200)
}

@Test func captureDocumentSerializesLiveDOM() async throws {
  let (engine, loaded) = try await captureFixturePage()
  let data = try await engine.runtime.captureDocument(
    pageID: loaded.id, includeComputedStyles: true, redactSensitive: false)
  #expect(data.html.contains("Headline"))
  #expect(data.html.contains(#"value="secret""#))
  #expect(data.stylesheets.contains { $0.sourceURL == nil && $0.css.contains("color: red") })
  #expect(!data.nodes.isEmpty)
  let header = try #require(data.nodes.first { $0.tag == "header" })
  #expect(header.selector.contains("#top"))
  #expect(header.bounds.width > 0 && header.bounds.height > 0)
  #expect(header.computedStyles["display"] != nil)
  #expect(data.resources.contains { $0.url == "https://example.test/i.png" && $0.kind == "image" })
  #expect(data.issues.contains { $0.code == "canvas-content" })
  #expect(data.issues.contains { $0.code == "frame-content" } == false)
}

@Test func captureDocumentRedactsSensitiveContent() async throws {
  let (engine, loaded) = try await captureFixturePage()
  let data = try await engine.runtime.captureDocument(
    pageID: loaded.id, includeComputedStyles: false, redactSensitive: true)
  #expect(!data.html.contains(#"value="secret""#))
  #expect(!data.html.contains("classified"))
  #expect(data.nodes.allSatisfy { $0.text?.contains("classified") != true })
  #expect(data.issues.contains { $0.code == "redaction-applied" })
}

@Test func cachedResourceBytesOnlyServesCache() async throws {
  let (engine, loaded) = try await captureFixturePage()
  let contextID = loaded.contextID
  #expect(
    try await engine.runtime.cachedResourceBytes(
      contextID: contextID, url: URL(string: "https://example.test/missing.css")!,
      maximumBytes: 1_000_000) == nil)
}

@Test func scrolledRenderMatchesViewportGeometry() async throws {
  let (engine, loaded) = try await captureFixturePage()
  let top = try await engine.runtime.render(pageID: loaded.id, origin: Point(x: 0, y: 0))
  #expect(top.width == 800 && top.height == 600)
  #expect(top.bytes.count == 800 * 600 * 4)
  _ = try await engine.runtime.scrollTo(pageID: loaded.id, x: 0, y: 50)
  let scrolled = try await engine.runtime.render(pageID: loaded.id, origin: Point(x: 0, y: 50))
  #expect(scrolled.width == 800 && scrolled.height == 600)
  #expect(scrolled.bytes.count == 800 * 600 * 4)
}

@Test func stabilityWaitReturnsImmediatelyOnEmptyPage() async throws {
  let engine = NativeBrowserEngine()
  let adapter = BrowserCaptureEngine(runtime: engine.runtime)
  let session = try await adapter.makeCaptureSession(
    viewport: CaptureViewport(width: 800, height: 600, scale: 1))
  try await session.waitForVisualStability(maxMilliseconds: 0)
  await session.close()
}

@Test func captureEntryPointsRejectWithoutNetwork() async throws {
  let engine = NativeBrowserEngine()
  let pagesBefore = await engine.runtime.fleetStats().totalPages
  #expect(throws: CaptureFailure.self) {
    try await engine.capturePage(
      url: URL(string: "ftp://example.test/file")!,
      into: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
  }
  var scaled = CaptureOptions()
  scaled.viewport.scale = 2
  #expect(throws: CaptureFailure.self) {
    try await engine.capturePage(
      url: captureFixtureURL,
      into: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
      options: scaled)
  }
  #expect(await engine.runtime.fleetStats().totalPages == pagesBefore)
}

@Test func dispatcherValidatesCaptureParameters() async throws {
  let dispatcher = AgentCommandDispatcher(engine: NativeBrowserEngine())
  let missing = await dispatcher.handle(AgentRequest(id: "m", method: .pageCapture))
  #expect(missing.error != nil)
  let badFormat = await dispatcher.handle(
    AgentRequest(
      id: "f", method: .pageCapture,
      params: [
        "url": .string("https://example.test/"), "path": .string("/tmp/aether-cap-nope"),
        "format": .string("tiff"),
      ]))
  #expect(badFormat.error != nil)
}
