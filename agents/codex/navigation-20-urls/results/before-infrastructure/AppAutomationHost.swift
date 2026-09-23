import AetherHumanUI
import AgentProtocol
import BrowserEngine
import EngineCore
import Foundation

@MainActor
final class AppAutomationHost {
  let ownership = AgentOwnershipRegistry()
  let authenticator: AgentSessionStore
  let socketPath: String
  let tokenPath: String
  private let task: Task<Void, Never>

  init(engine: NativeBrowserEngine) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aether-agent", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    socketPath = directory.appendingPathComponent("browser.sock").path
    tokenPath = directory.appendingPathComponent("access.token").path
    guard socketPath.utf8.count < 104 else { throw BrowserPortError.unsupported("automation socket path exceeding macOS limits") }
    let token = AgentAuth.generateToken()
    try AgentAuth.writeTokenFile(token, to: tokenPath)
    let authenticator = AgentSessionStore(expectedToken: token)
    self.authenticator = authenticator
    let ownership = self.ownership
    let server = AgentSocketServer(path: socketPath)
    let dispatcher = AgentCommandDispatcher(engine: engine)
    task = Task.detached {
      do {
        try await server.run(authenticator: authenticator) { principal, request in
          await dispatcher.handle(request, principal: principal, ownership: ownership)
        }
      } catch {
        FileHandle.standardError.write(Data("Automation server: \(error)\n".utf8))
      }
    }
  }

  deinit {
    task.cancel()
  }

  func shutdown() {
    task.cancel()
  }

  func authorize(_ context: ContextID) {
    ownership.bindContext(context.rawValue, to: authenticator.principal.id)
  }
}

extension AetherEngineAdapter: BrowserAutomationProviding {
  func authorizeAutomation(profileID: UUID) async throws -> String {
    let context = try await context(for: profileID)
    if automation == nil { automation = try AppAutomationHost(engine: engine) }
    guard let automation else { throw BrowserPortError.notConnected }
    automation.authorize(context)
    return "Local agents with the token file can control this profile.\nSocket: \(automation.socketPath)\nToken file: \(automation.tokenPath)"
  }
}
