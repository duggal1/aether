import AgentProtocol
import BrowserEngine
import Testing

@Test func authenticatedPageListingUsesContextOwnership() async throws {
  let engine = NativeBrowserEngine()
  let dispatcher = AgentCommandDispatcher(engine: engine)
  let ownership = AgentOwnershipRegistry()
  let owner = AgentPrincipal(id: "owner", kind: .agent)
  let stranger = AgentPrincipal(id: "stranger", kind: .agent)
  let context = await engine.createContext(name: "authenticated-list")
  ownership.bindContext(context.id.rawValue, to: owner.id)
  let request = AgentRequest(method: .pageList, params: ["context": .number(Double(context.id.rawValue))])
  let allowed = await dispatcher.handle(request, principal: owner, ownership: ownership)
  #expect(allowed.error == nil)
  #expect(allowed.result == .array([]))
  let denied = await dispatcher.handle(request, principal: stranger, ownership: ownership)
  #expect(denied.error?.code == "unauthorized")
  try await engine.destroyContext(context.id)
}
