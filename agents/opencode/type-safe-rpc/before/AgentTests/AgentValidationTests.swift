import AgentProtocol
import BrowserEngine
import Testing

@Test func invalidNumericAgentParametersReturnErrorsWithoutCrashing() async throws {
  let dispatcher = AgentCommandDispatcher(engine: NativeBrowserEngine())
  for value in [Double.nan, .infinity, -.infinity, 1e100, -1, 0.5] {
    for (method, params) in [
      (AgentMethod.pageCreate, ["context": JSONValue.number(value)]),
      (.pageCapture, ["url": .string("https://example.test"), "path": .string("/tmp/not-created"), "width": .number(value)]),
      (.fleetSweep, ["maxActive": .number(value)]),
    ] {
      let result = await dispatcher.handle(AgentRequest(method: method, params: params))
      #expect(result.error != nil)
    }
  }
  let ping = await dispatcher.handle(AgentRequest(method: .ping))
  #expect(ping.error == nil)
}
