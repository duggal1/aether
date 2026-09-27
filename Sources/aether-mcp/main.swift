import AgentMCP
import AgentProtocol
import Foundation

@main
struct AetherMCP {
  static func main() {
    do {
      let configuration = try MCPConfiguration(arguments: Array(CommandLine.arguments.dropFirst()))
      var server = AgentMCPServer { request, timeoutMilliseconds in
        let client = AgentSocketClient(
          path: configuration.socketPath,
          readTimeoutMilliseconds: timeoutMilliseconds)
        if let token = configuration.token {
          return try client.send(request, token: token)
        }
        return try client.send(request)
      }

      while let line = readLine() {
        guard let response = server.handle(Data(line.utf8)) else { continue }
        FileHandle.standardOutput.write(response)
        FileHandle.standardOutput.write(Data([0x0A]))
      }
    } catch {
      FileHandle.standardError.write(Data("aether-mcp: \(error)\n".utf8))
      Foundation.exit(2)
    }
  }
}

private struct MCPConfiguration {
  let socketPath: String
  let token: String?

  init(arguments: [String]) throws {
    var socketPath = "/tmp/native-browser-engine.sock"
    var token: String?
    var index = 0
    while index < arguments.count {
      guard index + 1 < arguments.count else { throw MCPConfigurationError.usage }
      switch arguments[index] {
      case "--socket":
        socketPath = arguments[index + 1]
      case "--token-file":
        token = try AgentAuth.readTokenFile(from: arguments[index + 1])
      default:
        throw MCPConfigurationError.usage
      }
      index += 2
    }
    self.socketPath = socketPath
    self.token = token
  }
}

private enum MCPConfigurationError: Error, CustomStringConvertible {
  case usage

  var description: String {
    switch self {
    case .usage:
      "Usage: aether-mcp [--socket PATH] [--token-file PATH]"
    }
  }
}
