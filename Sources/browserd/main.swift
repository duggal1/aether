import AgentProtocol
import BrowserEngine
import Foundation

@main
struct BrowserDaemon {
  static func main() async {
    let arguments = CommandLine.arguments.dropFirst()
    let path: String
    if let index = arguments.firstIndex(of: "--socket"),
      arguments.index(after: index) < arguments.endIndex
    {
      path = String(arguments[arguments.index(after: index)])
    } else {
      path = "/tmp/native-browser-engine.sock"
    }
    let tokenPath: String
    if let index = arguments.firstIndex(of: "--token-file"),
      arguments.index(after: index) < arguments.endIndex
    {
      tokenPath = String(arguments[arguments.index(after: index)])
    } else {
      tokenPath = path + ".token"
    }
    let unauthenticated = !arguments.contains("--token-file") || arguments.contains("--no-auth")

    let engine = NativeBrowserEngine()
    await engine.runtime.warmWebProcess()
    let dispatcher = AgentCommandDispatcher(engine: engine)
    let server = AgentSocketServer(path: path)

    if unauthenticated {
      FileHandle.standardError.write(
        Data("browserd listening on \(path) (no authentication)\n".utf8))
      do {
        try await server.run { request in
          await dispatcher.handle(request)
        }
      } catch {
        FileHandle.standardError.write(Data("browserd failed: \(error)\n".utf8))
        Foundation.exit(1)
      }
      return
    }

    let token = AgentAuth.generateToken()
    do {
      try AgentAuth.writeTokenFile(token, to: tokenPath)
    } catch {
      FileHandle.standardError.write(
        Data("browserd failed to write token file \(tokenPath): \(error)\n".utf8))
      Foundation.exit(1)
    }
    let authenticator = AgentSessionStore(expectedToken: token)
    let ownership = AgentOwnershipRegistry()
    FileHandle.standardError.write(
      Data("browserd listening on \(path), token at \(tokenPath)\n".utf8))
    do {
      try await server.run(authenticator: authenticator) { principal, request in
        await dispatcher.handle(request, principal: principal, ownership: ownership)
      }
    } catch {
      FileHandle.standardError.write(Data("browserd failed: \(error)\n".utf8))
      Foundation.exit(1)
    }
  }
}
