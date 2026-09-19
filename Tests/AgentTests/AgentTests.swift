import AgentProtocol
import BrowserEngine
import EngineCore
import Foundation
import Testing

@Test func runtimeCreatesIsolatedContextsAndPages() async throws {
  let engine = NativeBrowserEngine()
  let a = await engine.runtime.createContext(name: "a")
  let b = await engine.runtime.createContext(name: "b")
  let page = try await engine.runtime.createPage(
    contextID: a.id, viewport: Size(width: 640, height: 480))
  #expect(page.contextID == a.id)
  #expect(try await engine.runtime.listPages(contextID: b.id).isEmpty)
}

@Test func dispatcherExposesDeterministicContextAndPageLifecycle() async throws {
  let dispatcher = AgentCommandDispatcher(engine: NativeBrowserEngine())

  let ping = await dispatcher.handle(AgentRequest(id: "ping", method: .ping))
  #expect(ping.error == nil)
  #expect(ping.result?.object?["ok"]?.bool == true)

  let created = await dispatcher.handle(
    AgentRequest(id: "context", method: .contextCreate, params: ["name": .string("work")]))
  let context = try #require(created.result?.object?["id"]?.number)

  let page = await dispatcher.handle(
    AgentRequest(
      id: "page", method: .pageCreate,
      params: [
        "context": .number(context),
        "width": .number(900),
        "height": .number(700),
      ]))
  #expect(page.error == nil)
  #expect(page.result?.object?["width"]?.number == 900)
  #expect(page.result?.object?["height"]?.number == 700)

  let listed = await dispatcher.handle(AgentRequest(id: "list", method: .contextList))
  #expect(listed.error == nil)
  #expect(listed.result?.array?.count == 1)
  #expect(listed.result?.array?.first?.object?["pageCount"]?.number == 1)
}

@Test func profileCheckpointAndSuspendWorkOffline() async throws {
  let engine = NativeBrowserEngine()
  let context = await engine.runtime.createContext(name: "profiled")
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try await engine.runtime.openProfile(contextID: context.id, directory: directory)
  try await engine.runtime.checkpoint(contextID: context.id)
  let usage = try await engine.runtime.profileUsage(contextID: context.id)
  #expect(usage.databaseBytes > 0)
  #expect(usage.totalBytes == usage.databaseBytes + usage.blobBytes)
  try await engine.runtime.setCheckpoint(
    contextID: context.id, key: "k", value: Data("v".utf8))
  #expect(
    try await engine.runtime.checkpointValue(contextID: context.id, key: "k")
      == Data("v".utf8))
  let page = try await engine.runtime.createPage(contextID: context.id)
  let suspended = try await engine.runtime.suspendPage(page.id)
  #expect(suspended.loaded == false)
}
