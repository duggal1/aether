import AgentProtocol
import Foundation
import Testing

@Test func socketAuthHandshakeRoundTrip() async throws {
  let path = "/tmp/aether-auth-rt-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(path: path)
  let store = AgentSessionStore(expectedToken: "secret")
  let task = Task.detached {
    try await server.run(authenticator: store) { _, request in
      AgentResponse(id: request.id, result: .object(["ok": .bool(true)]))
    }
  }
  defer { task.cancel() }
  for _ in 0..<100 {
    if FileManager.default.fileExists(atPath: path) { break }
    try await Task.sleep(for: .milliseconds(20))
  }
  let client = AgentSocketClient(path: path)
  let ok = try client.send(AgentRequest(method: .ping), token: "secret")
  #expect(ok.error == nil)
  #expect(ok.result?.object?["ok"]?.bool == true)
}

@Test func socketAuthRejectsWrongAndMissingTokens() async throws {
  let path = "/tmp/aether-auth-rej-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(path: path)
  let store = AgentSessionStore(expectedToken: "secret")
  let task = Task.detached {
    try await server.run(authenticator: store) { _, request in
      AgentResponse(id: request.id, result: .object(["ok": .bool(true)]))
    }
  }
  defer { task.cancel() }
  for _ in 0..<100 {
    if FileManager.default.fileExists(atPath: path) { break }
    try await Task.sleep(for: .milliseconds(20))
  }
  let client = AgentSocketClient(path: path)
  let wrong = try client.send(AgentRequest(method: .ping), token: "wrong")
  #expect(wrong.error?.code == "unauthorized")
  let missing = try client.send(AgentRequest(method: .ping))
  #expect(missing.error?.code == "unauthorized")
}

@Test func socketAuthLocksOutAfterRepeatedFailures() async throws {
  let path = "/tmp/aether-auth-lock-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(path: path)
  let store = AgentSessionStore(expectedToken: "secret", maximumFailedAttempts: 2)
  let task = Task.detached {
    try await server.run(authenticator: store) { _, request in
      AgentResponse(id: request.id, result: .object(["ok": .bool(true)]))
    }
  }
  defer { task.cancel() }
  for _ in 0..<100 {
    if FileManager.default.fileExists(atPath: path) { break }
    try await Task.sleep(for: .milliseconds(20))
  }
  let client = AgentSocketClient(path: path)
  _ = try client.send(AgentRequest(method: .ping), token: "nope")
  _ = try client.send(AgentRequest(method: .ping), token: "nope")
  let locked = try client.send(AgentRequest(method: .ping), token: "secret")
  #expect(locked.error != nil)
}
