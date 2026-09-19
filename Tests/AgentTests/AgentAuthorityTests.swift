import AgentProtocol
import BrowserEngine
import Foundation
import Testing

private func command(
  _ dispatcher: AgentCommandDispatcher, _ method: AgentMethod,
  _ params: [String: JSONValue] = [:], capability: String? = nil
) async -> AgentResponse {
  var parameters = params
  if let capability { parameters["capability"] = .string(capability) }
  return await dispatcher.handle(AgentRequest(method: method, params: parameters))
}

@Test func daemonCapabilitiesRejectForgedOwnersAndCrossContextAccess() async throws {
  let dispatcher = AgentCommandDispatcher(
    engine: NativeBrowserEngine(), requireCapabilities: true)
  let a = await command(dispatcher, .contextCreate, ["name": .string("agent-a")])
  let b = await command(dispatcher, .contextCreate, ["name": .string("agent-b")])
  let aID = try #require(a.result?.object?["id"]?.number)
  let bID = try #require(b.result?.object?["id"]?.number)
  let aSecret = try #require(a.result?.object?["capability"]?.string)
  let bSecret = try #require(b.result?.object?["capability"]?.string)
  #expect(aSecret != bSecret)
  #expect(aSecret.count >= 64)
  #expect((await command(dispatcher, .contextList)).error?.code == "unauthorized")

  let aList = await command(dispatcher, .contextList, capability: aSecret)
  #expect(aList.result?.array?.count == 1)
  #expect(aList.result?.array?.first?.object?["id"]?.number == aID)
  let forged = await command(
    dispatcher, .contextCookies,
    ["context": .number(bID), "owner": .string("agent-b")],
    capability: aSecret)
  #expect(forged.error?.code == "unauthorized")
  let page = await command(
    dispatcher, .pageCreate, ["context": .number(bID)], capability: bSecret)
  let pageID = try #require(page.result?.object?["id"]?.number)
  let loaded = await command(
    dispatcher, .pageLoadHTML,
    ["page": .number(pageID), "url": .string("https://fixture.test/"),
      "html": .string("<html><head><title>Auth fixture</title></head><body>ok</body></html>")],
    capability: bSecret)
  #expect(loaded.error == nil)
  let crossPage = await command(
    dispatcher, .pageInspect, ["page": .number(pageID), "owner": .string("agent-b")],
    capability: aSecret)
  #expect(crossPage.error?.code == "unauthorized")
  #expect((await command(
    dispatcher, .pageInspect, ["page": .number(pageID)], capability: bSecret
  )).error == nil)
  let removed = await command(
    dispatcher, .contextDestroy, ["context": .number(bID)], capability: bSecret)
  #expect(removed.error == nil)
  #expect((await command(
    dispatcher, .contextList, capability: bSecret
  )).result?.array?.isEmpty == true)
}

@Test func daemonCapabilitiesFailClosedForUnscopedSensitiveActions() async throws {
  let dispatcher = AgentCommandDispatcher(
    engine: NativeBrowserEngine(), requireCapabilities: true)
  let created = await command(dispatcher, .contextCreate)
  let id = try #require(created.result?.object?["id"]?.number)
  let secret = try #require(created.result?.object?["capability"]?.string)
  let context = ["context": JSONValue.number(id)]
  let sensitive: [AgentMethod] = [
    .contextOpenProfile, .pageCapture, .sessionCreate, .sessionList,
    .fleetPages, .dialogResolve,
  ]
  for method in sensitive {
    #expect((await command(dispatcher, method, context, capability: secret))
      .error?.code == "unauthorized")
  }
  #expect((await command(
    dispatcher, .contextDownload,
    ["context": .number(id), "path": .string("/Users/other/secret")],
    capability: secret
  )).error?.code == "unauthorized")
  #expect((await command(
    dispatcher, .contextSetPermission,
    ["context": .number(id), "decision": .string("allow")],
    capability: secret
  )).error?.code == "unauthorized")
}
