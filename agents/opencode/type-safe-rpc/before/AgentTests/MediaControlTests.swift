import AgentProtocol
import BrowserEngine
import EngineCore
import EngineRuntime
import Foundation
import Testing

private func mediaFixture(_ name: String) -> String {
  URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fixtures/media/\(name)").absoluteString
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

@Test func mediaElementLifecycleThroughAgent() async throws {
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
      "url": .string("https://example.test/media"),
      "html": .string(
        "<html><body><video id=\"v\" src=\"\(mediaFixture("sample.mp4"))\"></video></body></html>"),
    ]))
  #expect(loaded.error == nil)
  let node = try await mediaNode(dispatcher: dispatcher, page: pageID)
  let listed = await dispatcher.handle(AgentRequest(
    method: .pageMedia, params: ["page": .number(pageID)]))
  #expect(listed.result?.array?.first?.object?["tag"]?.string == "video")
  #expect(listed.result?.array?.first?.object?["paused"]?.bool == true)

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
  #expect(advanced)
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

@Test func mediaJavaScriptBindings() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "media-js")
  let page = try await engine.runtime.createPage(contextID: context.id)
  _ = try await engine.runtime.loadHTML(
    pageID: page.id,
    html:
      "<html><body><video id=\"v\" src=\"\(mediaFixture("sample.mp4"))\"></video></body></html>",
    url: URL(string: "https://example.test/js-media")!)
  let canPlay = try await engine.runtime.evaluate(
    pageID: page.id, source: "document.getElementById('v').canPlayType('video/mp4')")
  #expect(canPlay.value == "probably")
  let noPlay = try await engine.runtime.evaluate(
    pageID: page.id, source: "document.getElementById('v').canPlayType('video/unknown')")
  #expect(noPlay.value == "")
  _ = try await engine.runtime.evaluate(
    pageID: page.id, source: "var watched=false; var v=document.getElementById('v'); v.addEventListener('playing',()=>{watched=true;}); v.play();")
  var observed = false
  for _ in 0..<100 {
    try await Task.sleep(for: .milliseconds(100))
    let check = try await engine.runtime.evaluate(pageID: page.id, source: "watched")
    if check.value == "true" {
      observed = true
      break
    }
  }
  #expect(observed)
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
