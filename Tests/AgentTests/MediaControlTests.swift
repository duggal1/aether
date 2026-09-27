import AppKit
import AgentProtocol
import BrowserEngine
import EngineCore
import EngineRuntime
import Foundation
import Testing
import WebKit

@MainActor
private func present(_ view: WKWebView) -> NSWindow {
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
    styleMask: [.borderless], backing: .buffered, defer: false)
  // Programmatically created windows default to isReleasedWhenClosed == true, so
  // `close()` releases the AppKit object while ARC still holds a strong reference and
  // releases it again at the end of the test. That over-release crashed the whole
  // AgentTests bundle in `objc_release` (TISSUE-010).
  window.isReleasedWhenClosed = false
  window.alphaValue = 0
  window.ignoresMouseEvents = true
  window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
  window.contentView?.addSubview(view)
  view.frame = window.contentView?.bounds ?? .zero
  window.orderFront(nil)
  return window
}

@MainActor
private func dismissTestWindow(_ window: NSWindow) {
  for subview in window.contentView?.subviews ?? [] {
    (subview as? WKWebView)?.stopLoading()
    subview.removeFromSuperview()
  }
  window.close()
}

@MainActor
private func withPresentedPage<Value>(
  runtime: BrowserRuntime, pageID: PageID, contextID: ContextID,
  operation: @MainActor () async throws -> Value
) async throws -> Value {
  let window: NSWindow
  do {
    window = present(try await runtime.webSurface(pageID: pageID))
  } catch {
    try? await runtime.destroyContext(contextID)
    throw error
  }
  do {
    let value = try await operation()
    try? await runtime.closePage(pageID)
    try? await runtime.destroyContext(contextID)
    dismissTestWindow(window)
    return value
  } catch {
    try? await runtime.closePage(pageID)
    try? await runtime.destroyContext(contextID)
    dismissTestWindow(window)
    throw error
  }
}

private func mediaNode(
  dispatcher: AgentCommandDispatcher, page: Double
) async throws -> (Double, Double) {
  let listed = await dispatcher.handle(AgentRequest(method: .pageMedia, params: ["page": .number(page)]))
  try #require(listed.error == nil)
  let element = try #require(listed.result?.array?.first?.object)
  let index = try #require(element["nodeIndex"]?.number)
  let generation = try #require(element["nodeGeneration"]?.number)
  return (index, generation)
}

private func mediaControl(
  dispatcher: AgentCommandDispatcher, page: Double, node: (Double, Double), action: String,
  extra: [String: JSONValue] = [:]
) async -> AgentResponse {
  var params: [String: JSONValue] = [
    "page": .number(page), "nodeIndex": .number(node.0),
    "nodeGeneration": .number(node.1), "action": .string(action),
  ]
  for (key, value) in extra { params[key] = value }
  return await dispatcher.handle(AgentRequest(method: .pageMediaControl, params: params))
}

@Test @MainActor func mediaElementLifecycleThroughAgent() async throws {
  let fixturePort = ValidationFixtureServer.randomPort()
  let fixtureServer = try ValidationFixtureServer.start(port: fixturePort)
  defer { fixtureServer.terminate() }
  let engine = NativeBrowserEngine()
  let dispatcher = AgentCommandDispatcher(engine: engine)
  let context = await dispatcher.handle(AgentRequest(method: .contextCreate))
  let contextID = try #require(context.result?.object?["id"]?.number)
  let page = await dispatcher.handle(AgentRequest(
    method: .pageCreate, params: ["context": .number(contextID)]))
  let pageID = try #require(page.result?.object?["id"]?.number)
  try await withPresentedPage(
    runtime: engine.runtime,
    pageID: PageID(rawValue: UInt64(pageID)),
    contextID: ContextID(rawValue: UInt64(contextID)))
  {
    let loaded = await dispatcher.handle(AgentRequest(
      method: .pageNavigate,
      params: [
        "page": .number(pageID),
        "url": .string(ValidationFixtureServer.url(fixturePort, "/media").absoluteString),
      ]))
    #expect(loaded.error == nil)
    let node = try await mediaNode(dispatcher: dispatcher, page: pageID)
    let listed = await dispatcher.handle(AgentRequest(
      method: .pageMedia, params: ["page": .number(pageID)]))
    #expect(listed.result?.array?.first?.object?["tag"]?.string == "video")
    #expect(listed.result?.array?.first?.object?["paused"]?.bool == true)
    #expect(listed.result?.array?.first?.object?["muted"]?.bool == true)
    let loadedMedia = await mediaControl(
      dispatcher: dispatcher, page: pageID, node: node, action: "load")
    #expect(loadedMedia.error == nil)

    let playing = await mediaControl(
      dispatcher: dispatcher, page: pageID, node: node, action: "play")
    #expect(playing.error == nil)
    var advanced = false
    for _ in 0..<100 {
      let state = await dispatcher.handle(AgentRequest(
        method: .pageMedia, params: ["page": .number(pageID)]))
      if (state.result?.array?.first?.object?["currentTime"]?.number ?? 0) > 0.3 {
        advanced = true
        break
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    let debugState = await dispatcher.handle(AgentRequest(
      method: .pageEvaluate,
      params: [
        "page": .number(pageID),
        "source": .string("JSON.stringify((()=>{const v=document.getElementById('v');return {href:location.href,base:document.baseURI,attribute:v.getAttribute('src'),source:v.src,src:v.currentSrc,networkState:v.networkState,readyState:v.readyState,error:v.error&&{code:v.error.code,message:v.error.message},paused:v.paused,currentTime:v.currentTime}})())"),
      ]))
    let (requestData, _) = try await URLSession.shared.data(
      from: ValidationFixtureServer.url(fixturePort, "/requests"))
    let debugMessage = debugState.result?.object?["value"]?.string
      ?? String(describing: debugState.error)
    let requestHistory = String(decoding: requestData, as: UTF8.self)
    #expect(advanced, "Media diagnostic: \(debugMessage); requests: \(requestHistory)")
    let paused = await mediaControl(
      dispatcher: dispatcher, page: pageID, node: node, action: "pause")
    #expect(paused.result?.object?["paused"]?.bool == true)
    let seeked = await mediaControl(
      dispatcher: dispatcher, page: pageID, node: node, action: "seek",
      extra: ["time": .number(2.0)])
    #expect(abs((seeked.result?.object?["currentTime"]?.number ?? -1) - 2.0) < 0.35)
    let quiet = await mediaControl(
      dispatcher: dispatcher, page: pageID, node: node, action: "setVolume",
      extra: ["value": .number(0.5)])
    #expect(quiet.result?.object?["volume"]?.number == 0.5)
    let denied = await mediaControl(
      dispatcher: dispatcher, page: pageID, node: (9999, 1), action: "play")
    #expect(denied.error != nil)
    let badAction = await dispatcher.handle(AgentRequest(
      method: .pageMediaControl,
      params: [
        "page": .number(pageID), "nodeIndex": .number(node.0),
        "nodeGeneration": .number(node.1), "action": .string("rewind"),
      ]))
    #expect(badAction.error != nil)
  }
}

@Test @MainActor func mediaJavaScriptBindings() async throws {
  let fixturePort = ValidationFixtureServer.randomPort()
  let fixtureServer = try ValidationFixtureServer.start(port: fixturePort)
  defer { fixtureServer.terminate() }
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "media-js")
  let page = try await engine.runtime.createPage(contextID: context.id)
  try await withPresentedPage(runtime: engine.runtime, pageID: page.id, contextID: context.id) {
    try await engine.runtime.navigate(
      pageID: page.id, to: ValidationFixtureServer.url(fixturePort, "/media"))
    let isMuted = try await engine.runtime.evaluate(
      pageID: page.id, source: "document.getElementById('v').muted")
    #expect(isMuted.value == "true")
    let canPlay = try await engine.runtime.evaluate(
      pageID: page.id, source: "document.getElementById('v').canPlayType('video/mp4')")
    #expect(canPlay.value == "maybe" || canPlay.value == "probably")
    let noPlay = try await engine.runtime.evaluate(
      pageID: page.id, source: "document.getElementById('v').canPlayType('video/unknown')")
    #expect(noPlay.value == "")
    _ = try await engine.runtime.evaluate(
      pageID: page.id, source: "var watched=false; var v=document.getElementById('v'); v.addEventListener('playing',()=>{watched=true;}); v.load(); v.play().catch(e=>window.playError=e.name+':'+e.message); 'requested';")
    var observed = false
    for _ in 0..<100 {
      try await Task.sleep(for: .milliseconds(100))
      let check = try await engine.runtime.evaluate(pageID: page.id, source: "watched")
      if check.value == "true" {
        observed = true
        break
      }
    }
    let playbackDiagnostic = try await engine.runtime.evaluate(
      pageID: page.id,
      source: "JSON.stringify((()=>{const v=document.getElementById('v');return {watched:window.watched,playError:window.playError,paused:v.paused,currentTime:v.currentTime,currentSrc:v.currentSrc,networkState:v.networkState,readyState:v.readyState,error:v.error&&{code:v.error.code,message:v.error.message}}})())")
    #expect(observed, "Playback event diagnostic: \(playbackDiagnostic.value)")
    var advanced = false
    for _ in 0..<100 {
      let time = try await engine.runtime.evaluate(
        pageID: page.id, source: "document.getElementById('v').currentTime")
      if (Double(time.value) ?? 0) > 0.2 {
        advanced = true
        break
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    #expect(advanced)
    _ = try await engine.runtime.evaluate(
      pageID: page.id, source: "document.getElementById('v').pause()")
  }
}

@Test @MainActor func evaluatePreservesJavaScriptScalarValues() async throws {
  let fixturePort = ValidationFixtureServer.randomPort()
  let fixtureServer = try ValidationFixtureServer.start(port: fixturePort)
  defer { fixtureServer.terminate() }
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "javascript-scalars")
  let page = try await engine.runtime.createPage(contextID: context.id)
  try await withPresentedPage(runtime: engine.runtime, pageID: page.id, contextID: context.id) {
    try await engine.runtime.navigate(
      pageID: page.id, to: ValidationFixtureServer.url(fixturePort, "/fast"))

    let trueValue = try await engine.runtime.evaluate(pageID: page.id, source: "true")
    let falseValue = try await engine.runtime.evaluate(pageID: page.id, source: "false")
    let nullValue = try await engine.runtime.evaluate(pageID: page.id, source: "null")
    let numberValue = try await engine.runtime.evaluate(pageID: page.id, source: "42.5")
    let stringValue = try await engine.runtime.evaluate(pageID: page.id, source: "'aether'")

    #expect(trueValue.value == "true")
    #expect(falseValue.value == "false")
    #expect(nullValue.value == "null")
    #expect(numberValue.value == "42.5")
    #expect(stringValue.value == "aether")
  }
}
