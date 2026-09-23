import AgentProtocol
import Darwin
import Foundation
import Testing

private func framingConnection(_ path: String) throws -> Int32 {
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { throw AgentTransportError.socket("socket") }
  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  let bytes = Array(path.utf8CString)
  withUnsafeMutableBytes(of: &address.sun_path) { raw in
    raw.initializeMemory(as: UInt8.self, repeating: 0)
    for index in bytes.indices { raw[index] = UInt8(bitPattern: bytes[index]) }
  }
  let result = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
  }
  guard result == 0 else { close(fd); throw AgentTransportError.socket("connect") }
  var timeout = timeval(tv_sec: 3, tv_usec: 0)
  _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  return fd
}

private func framingWait(_ path: String) async throws {
  for _ in 0..<150 {
    if FileManager.default.fileExists(atPath: path) { return }
    try await Task.sleep(for: .milliseconds(20))
  }
  throw AgentTransportError.socket("Listener did not start")
}

private func framingRead(_ fd: Int32, count: Int) throws -> [AgentResponse] {
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 8192)
  while data.filter({ $0 == 10 }).count < count {
    let received = recv(fd, &buffer, buffer.count, 0)
    guard received > 0 else { throw AgentTransportError.protocolError("Missing pipeline responses") }
    data.append(contentsOf: buffer[..<received])
  }
  return try data.split(separator: 10).map { try AgentCodec.decodeResponse(Data($0)) }
}

@Test func socketKeepsEveryPipelinedMessageAndAcceptsAnotherBatch() async throws {
  let path = "/tmp/aether-frames-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(path: path)
  let task = Task.detached {
    try await server.run { AgentResponse(id: $0.id, result: .bool(true)) }
  }
  defer { task.cancel() }
  try await framingWait(path)
  let fd = try framingConnection(path)
  defer { close(fd) }
  for batch in 0..<3 {
    var payload = Data()
    for index in 0..<100 {
      payload.append(try AgentCodec.encode(AgentRequest(id: "\(batch)-\(index)", method: .ping)))
    }
    let sent = payload.withUnsafeBytes { send(fd, $0.baseAddress, payload.count, 0) }
    #expect(sent == payload.count)
    let responses = try framingRead(fd, count: 100)
    #expect(responses.map(\.id) == (0..<100).map { "\(batch)-\($0)" })
  }
}

@Test func socketCoalescedAuthenticationAndCommandPreserveBothFrames() async throws {
  let path = "/tmp/aether-coalesce-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(path: path)
  let store = AgentSessionStore(expectedToken: "secret")
  let task = Task.detached {
    try await server.run(authenticator: store) { _, request in
      AgentResponse(id: request.id, result: .bool(true))
    }
  }
  defer { task.cancel() }
  try await framingWait(path)
  let fd = try framingConnection(path)
  defer { close(fd) }
  let payload = Data("secret\n".utf8) + (try AgentCodec.encode(AgentRequest(id: "ping", method: .ping)))
  _ = payload.withUnsafeBytes { send(fd, $0.baseAddress, payload.count, 0) }
  let responses = try framingRead(fd, count: 2)
  #expect(responses.map(\.id) == ["auth", "ping"])
}

@Test func socketIdleClientsDoNotStarveCommandExecution() async throws {
  let path = "/tmp/aether-starve-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(path: path)
  let task = Task.detached {
    try await server.run { request in
      await Task.yield()
      return AgentResponse(id: request.id, result: .bool(true))
    }
  }
  defer { task.cancel() }
  try await framingWait(path)
  var idle: [Int32] = []
  defer { for fd in idle { close(fd) } }
  for _ in 0..<24 { idle.append(try framingConnection(path)) }
  try await Task.sleep(for: .milliseconds(100))
  let client = AgentSocketClient(path: path, readTimeoutMilliseconds: 2_000)
  let start = Date()
  #expect(try client.send(AgentRequest(method: .ping)).error == nil)
  #expect(Date().timeIntervalSince(start) < 2)
}

@Test func secondListenerCannotUnlinkLiveSocket() async throws {
  let path = "/tmp/aether-duplicate-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(path: path)
  let task = Task.detached {
    try await server.run { AgentResponse(id: $0.id, result: .bool(true)) }
  }
  defer { task.cancel() }
  try await framingWait(path)
  do {
    try await server.run { AgentResponse(id: $0.id, result: .null) }
    Issue.record("Second listener replaced the live endpoint")
  } catch { }
  #expect(try AgentSocketClient(path: path).send(AgentRequest(method: .ping)).result?.bool == true)
}
