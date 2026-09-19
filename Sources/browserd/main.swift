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
    let engine = NativeBrowserEngine()
    let dispatcher = AgentCommandDispatcher(engine: engine)
    let server = AgentSocketServer(path: path)
    FileHandle.standardError.write(Data("browserd listening on \(path)\n".utf8))
    do {
      try await server.run { request in
        await dispatcher.handle(request)
      }
    } catch {
      FileHandle.standardError.write(Data("browserd failed: \(error)\n".utf8))
      Foundation.exit(1)
    }
  }
}
