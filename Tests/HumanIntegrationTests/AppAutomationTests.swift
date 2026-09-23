import AetherHumanUI
import AgentProtocol
import Foundation
import Testing
@testable import AetherApp

@Test @MainActor func appAutomationUsesVisibleTabsAndReportsReadiness() throws {
  let adapter = AetherEngineAdapter()
  let workspace = BrowserWorkspace(engine: adapter)
  let commands = AppAutomationCommands(workspace: workspace)
  func request(_ method: String, _ params: [String: JSONValue] = [:]) -> AgentRequest {
    AgentRequest(id: "test", method: method, params: params)
  }
  #expect(commands.handle(request("app.status")).result?["ready"]?.bool == false)
  let window = BrowserWindowModel(workspace: workspace)
  #expect(commands.handle(request("app.status")).result?["ready"]?.bool == true)
  let opened = commands.handle(request("app.open", ["url": .string("https://example.com/pricing")]))
  let id = try #require(opened.result?["id"]?.string)
  #expect(window.selected?.id.uuidString == id)
  #expect(window.selected?.pendingURL == "https://example.com/pricing")
  let closed = commands.handle(request("app.close", ["tab": .string(id)]))
  #expect(closed.error == nil)
  #expect(!window.tabs.contains { $0.id.uuidString == id })
  window.closeWindow()
}
