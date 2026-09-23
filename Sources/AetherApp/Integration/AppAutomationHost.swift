import AetherHumanUI
import AgentProtocol
import BrowserEngine
import Foundation

@MainActor
final class AppAutomationHost {
  let socketPath: String
  private let task: Task<Void, Never>

  init(engine: NativeBrowserEngine, workspace: BrowserWorkspace) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aether-agent", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    socketPath = directory.appendingPathComponent("browser.sock").path
    guard socketPath.utf8.count < 104 else { throw BrowserPortError.unsupported("automation socket path exceeding macOS limits") }
    let server = AgentSocketServer(path: socketPath)
    let dispatcher = AgentCommandDispatcher(engine: engine)
    let commands = AppAutomationCommands(workspace: workspace)
    task = Task.detached {
      do {
        try await server.run { request in
          if request.method.hasPrefix("app.") { return await commands.handle(request) }
          return await dispatcher.handle(request)
        }
      } catch {
        FileHandle.standardError.write(Data("Automation server: \(error)\n".utf8))
      }
    }
  }

  deinit { task.cancel() }
  func shutdown() { task.cancel() }
}

extension AetherEngineAdapter: BrowserAutomationProviding {
  func startAutomation(workspace: BrowserWorkspace) {
    guard automation == nil else { return }
    do { automation = try AppAutomationHost(engine: engine, workspace: workspace) }
    catch { workspace.persistenceError = "Local automation: \(error)" }
  }

  func authorizeAutomation(profileID: UUID) async throws -> String {
    guard let automation else { throw BrowserPortError.notConnected }
    return "Local agents have full browser access. No token is required.\nSocket: \(automation.socketPath)"
  }
}
