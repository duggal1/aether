import BrowserEngine
import EngineCore
import EngineRuntime
import Foundation
import Testing

@Test func surfacePreservesLivePageAcrossAttachmentAndDetach() async throws {
  let runtime = NativeBrowserEngine().runtime
  let context = await runtime.createContext(name: "surface")
  let page = try await runtime.createPage(contextID: context.id, viewport: Size(width: 160, height: 120))
  _ = try await runtime.loadHTML(pageID: page.id,
    html: "<div id='target' style='height:400px;background:red'>before</div>",
    url: URL(string: "https://surface.test")!)
  _ = try await runtime.evaluate(pageID: page.id, source: "let retainedValue = 41")
  let node = try #require(try await runtime.query(pageID: page.id, selector: "#target"))
  let first = try await runtime.frame(pageID: page.id)
  let surface = try await runtime.attachSurface(pageID: page.id)
  let attached = try await runtime.requestFrame(surface, after: first.revision)
  #expect(attached.pixels == first.pixels)
  #expect(attached.damage.isEmpty)
  #expect(attached.report.rasterMilliseconds == 0)
  _ = try await runtime.evaluate(pageID: page.id,
    source: "document.getElementById('target').textContent = 'after'")
  let changed = try await runtime.requestFrame(surface, after: attached.revision)
  #expect(changed.revision > attached.revision)
  #expect(changed.mutationVersion > attached.mutationVersion)
  #expect(!changed.damage.isEmpty)
  #expect(changed.pixels != attached.pixels)
  _ = try await runtime.scrollTo(pageID: page.id, x: 0, y: 40)
  let scrolled = try await runtime.requestFrame(surface, after: changed.revision)
  #expect(scrolled.scroll == Point(x: 0, y: 40))
  #expect(scrolled.report.layoutMilliseconds == 0)
  #expect(scrolled.pixels == (try await runtime.render(pageID: page.id, origin: scrolled.scroll)))
  try await runtime.detachSurface(surface)
  #expect(try await runtime.query(pageID: page.id, selector: "#target")?.id == node.id)
  #expect(try await runtime.evaluate(pageID: page.id, source: "retainedValue + 1").value == "42")
  #expect(try await runtime.scrollOffset(pageID: page.id) == scrolled.scroll)
  let replacement = try await runtime.attachSurface(pageID: page.id)
  await #expect(throws: PageSurfaceError.detached) { try await runtime.requestFrame(surface) }
  let current = try await runtime.requestFrame(replacement)
  #expect(current.pixels == scrolled.pixels)
}

@Test func surfaceRejectsContendersAndInvalidatedHandles() async throws {
  let runtime = NativeBrowserEngine().runtime
  let context = await runtime.createContext(name: "surface")
  let page = try await runtime.createPage(contextID: context.id)
  let surface = try await runtime.attachSurface(pageID: page.id)
  await #expect(throws: PageSurfaceError.alreadyAttached) {
    try await runtime.attachSurface(pageID: page.id)
  }
  await #expect(throws: BrowserRuntimeError.self) { try await runtime.requestFrame(surface) }
  try await runtime.closePage(page.id)
  await #expect(throws: BrowserRuntimeError.self) { try await runtime.requestFrame(surface) }
}

@Test func surfaceResizeAndDiscardInvalidatePixelsWithoutReusingOldFrame() async throws {
  let runtime = NativeBrowserEngine().runtime
  let context = await runtime.createContext(name: "surface")
  let page = try await runtime.createPage(contextID: context.id, viewport: Size(width: 100, height: 100))
  _ = try await runtime.loadHTML(pageID: page.id, html: "<p>hello</p>", url: URL(string: "https://surface.test")!)
  let surface = try await runtime.attachSurface(pageID: page.id)
  let first = try await runtime.requestFrame(surface)
  _ = try await runtime.resizeSurface(surface, viewport: Size(width: 200, height: 150))
  let resized = try await runtime.requestFrame(surface, after: first.revision)
  #expect(resized.pixels.width == 200)
  #expect(resized.pixels.height == 150)
  #expect(resized.report.ramBytesEstimate == 200 * 150 * 4)
  #expect(!resized.damage.isEmpty)
  _ = try await runtime.suspendPage(page.id)
  await #expect(throws: BrowserRuntimeError.self) { try await runtime.requestFrame(surface) }
  _ = try await runtime.loadHTML(pageID: page.id, html: "<p>restored</p>", url: URL(string: "https://surface.test")!)
  let restored = try await runtime.requestFrame(surface, after: resized.revision)
  #expect(restored.revision > resized.revision)
  #expect(restored.pixels != resized.pixels)
}

@Test func surfaceHitTestDispatchesIntoTheExistingDOMEventRuntime() async throws {
  let runtime = NativeBrowserEngine().runtime
  let context = await runtime.createContext(name: "input")
  let page = try await runtime.createPage(contextID: context.id, viewport: Size(width: 200, height: 200))
  _ = try await runtime.loadHTML(pageID: page.id,
    html: "<button id='button' style='width:100px;height:50px'>Click</button>",
    url: URL(string: "https://surface.test")!)
  _ = try await runtime.evaluate(pageID: page.id,
    source: "let clicks = 0; document.getElementById('button').addEventListener('click', function() { clicks = clicks + 1; })")
  let button = try #require(try await runtime.query(pageID: page.id, selector: "#button"))
  let bounds = try #require(button.bounds)
  let surface = try await runtime.attachSurface(pageID: page.id)
  let x = bounds.maxX - 2
  let y = bounds.maxY - 2
  #expect(try await runtime.nodeAtSurfacePoint(surface, x: x, y: y)?.id == button.id)
  _ = try await runtime.clickSurface(surface, x: x, y: y)
  #expect(try await runtime.evaluate(pageID: page.id, source: "clicks").value == "1")
  try await runtime.detachSurface(surface)
  await #expect(throws: PageSurfaceError.detached) { try await runtime.clickSurface(surface, x: x, y: y) }
  #expect(try await runtime.evaluate(pageID: page.id, source: "clicks").value == "1")
}
