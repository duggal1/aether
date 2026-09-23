import AgentProtocol
import BrowserEngine
import Foundation
import Testing

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

private func waitForSocket(_ path: String) async throws {
  for _ in 0..<150 {
    if FileManager.default.fileExists(atPath: path) { return }
    try await Task.sleep(for: .milliseconds(20))
  }
  Issue.record("socket never appeared at \(path)")
}

@Test func socketIdleClientIsReleasedByReadTimeout() async throws {
  let path = "/tmp/aether-idle-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(
    path: path, idleReadTimeoutMilliseconds: 150, acceptPollMilliseconds: 20)
  let task = Task.detached {
    try await server.run { _ in
      AgentResponse(id: "never", result: .null)
    }
  }
  defer { task.cancel() }
  try await waitForSocket(path)

  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  #expect(fd >= 0)
  defer { if fd >= 0 { close(fd) } }
  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  let bytes = Array(path.utf8CString)
  withUnsafeMutableBytes(of: &address.sun_path) { raw in
    raw.initializeMemory(as: UInt8.self, repeating: 0)
    for index in bytes.indices { raw[index] = UInt8(bitPattern: bytes[index]) }
  }
  let connected = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
  }
  #expect(connected == 0)

  var buffer = [UInt8](repeating: 0, count: 256)
  let start = Date()
  var closed = false
  while Date().timeIntervalSince(start) < 5 {
    let result = recv(fd, &buffer, buffer.count, 0)
    if result == 0 || result < 0 {
      closed = true
      break
    }
  }
  let elapsed = Date().timeIntervalSince(start)
  #expect(closed)
  #expect(elapsed < 5)
}

@Test func socketPartialMessageStallsThenTimesOut() async throws {
  let path = "/tmp/aether-partial-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(
    path: path, idleReadTimeoutMilliseconds: 150, acceptPollMilliseconds: 20)
  let task = Task.detached {
    try await server.run { _ in
      AgentResponse(id: "never", result: .null)
    }
  }
  defer { task.cancel() }
  try await waitForSocket(path)

  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  #expect(fd >= 0)
  defer { if fd >= 0 { close(fd) } }
  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  let bytes = Array(path.utf8CString)
  withUnsafeMutableBytes(of: &address.sun_path) { raw in
    raw.initializeMemory(as: UInt8.self, repeating: 0)
    for index in bytes.indices { raw[index] = UInt8(bitPattern: bytes[index]) }
  }
  let connected = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
  }
  #expect(connected == 0)
  let partial = Data("{\"id\":\"x\",".utf8)
  let sent = partial.withUnsafeBytes { raw in
    send(fd, raw.baseAddress, raw.count, 0)
  }
  #expect(sent == partial.count)

  let readStart = Date()
  var buffer = [UInt8](repeating: 0, count: 256)
  var closed = false
  while Date().timeIntervalSince(readStart) < 5 {
    let result = recv(fd, &buffer, buffer.count, 0)
    if result == 0 || result < 0 {
      closed = true
      break
    }
  }
  let elapsed = Date().timeIntervalSince(readStart)
  #expect(closed)
  #expect(elapsed < 5)
}

@Test func socketAbruptClientDisconnectDoesNotKillServer() async throws {
  let path = "/tmp/aether-abrupt-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(path: path, acceptPollMilliseconds: 20)
  let task = Task.detached {
    try await server.run { _ in
      AgentResponse(id: "x", result: .object(["ok": .bool(true)]))
    }
  }
  defer { task.cancel() }
  try await waitForSocket(path)

  for _ in 0..<5 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { continue }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
      raw.initializeMemory(as: UInt8.self, repeating: 0)
      for index in bytes.indices { raw[index] = UInt8(bitPattern: bytes[index]) }
    }
    _ = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    close(fd)
  }

  try await Task.sleep(for: .milliseconds(100))
  let client = AgentSocketClient(path: path)
  let response = try client.send(AgentRequest(method: .ping))
  #expect(response.error == nil)
  #expect(response.id == "x")
}

@Test func socketNormalShutdownUnlinksAndStopsAccepting() async throws {
  let path = "/tmp/aether-shutdown-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(path: path, acceptPollMilliseconds: 20)
  let task = Task.detached {
    try await server.run { _ in
      AgentResponse(id: "x", result: .null)
    }
  }
  try await waitForSocket(path)
  let client = AgentSocketClient(path: path)
  _ = try client.send(AgentRequest(method: .ping))

  task.cancel()
  let deadline = Date().addingTimeInterval(5)
  while FileManager.default.fileExists(atPath: path), Date() < deadline {
    try await Task.sleep(for: .milliseconds(20))
  }
  #expect(!FileManager.default.fileExists(atPath: path))
  _ = try? await task.value
}

@Test func socketCancellationReleasesBlockedIdleClientPromptly() async throws {
  let path = "/tmp/aether-cancel-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(
    path: path, idleReadTimeoutMilliseconds: 30_000, acceptPollMilliseconds: 20)
  let task = Task.detached {
    try await server.run { _ in
      AgentResponse(id: "never", result: .null)
    }
  }
  try await waitForSocket(path)

  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  #expect(fd >= 0)
  defer { if fd >= 0 { close(fd) } }
  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  let bytes = Array(path.utf8CString)
  withUnsafeMutableBytes(of: &address.sun_path) { raw in
    raw.initializeMemory(as: UInt8.self, repeating: 0)
    for index in bytes.indices { raw[index] = UInt8(bitPattern: bytes[index]) }
  }
  let connected = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
  }
  #expect(connected == 0)

  let start = Date()
  task.cancel()
  _ = try? await task.value
  let elapsed = Date().timeIntervalSince(start)
  #expect(elapsed < 5)

  var buffer = [UInt8](repeating: 0, count: 16)
  let recvResult = recv(fd, &buffer, buffer.count, 0)
  #expect(recvResult == 0 || recvResult < 0)
}

@Test func socketEnforcesConnectionLimit() async throws {
  let path = "/tmp/aether-limit-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(
    path: path, maxConcurrentConnections: 2, idleReadTimeoutMilliseconds: 2_000,
    acceptPollMilliseconds: 20)
  let task = Task.detached {
    try await server.run { request in
      try? await Task.sleep(for: .milliseconds(50))
      return AgentResponse(id: request.id, result: .null)
    }
  }
  defer { task.cancel() }
  try await waitForSocket(path)

  var held: [Int32] = []
  defer {
    for fd in held { close(fd) }
  }
  for _ in 0..<2 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { continue }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
      raw.initializeMemory(as: UInt8.self, repeating: 0)
      for index in bytes.indices { raw[index] = UInt8(bitPattern: bytes[index]) }
    }
    let connected = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    if connected == 0 {
      held.append(fd)
      let payload = Data((("{\"id\":\"hold\(held.count)\",\"method\":\"ping\",\"params\":{}}\n")).utf8)
      _ = payload.withUnsafeBytes { send(fd, $0.baseAddress, payload.count, 0) }
    }
  }
  try await Task.sleep(for: .milliseconds(30))

  let extra = socket(AF_UNIX, SOCK_STREAM, 0)
  #expect(extra >= 0)
  defer { if extra >= 0 { close(extra) } }
  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  let bytes = Array(path.utf8CString)
  withUnsafeMutableBytes(of: &address.sun_path) { raw in
    raw.initializeMemory(as: UInt8.self, repeating: 0)
    for index in bytes.indices { raw[index] = UInt8(bitPattern: bytes[index]) }
  }
  let connected = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      connect(extra, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
  }
  if connected == 0 {
    var buffer = [UInt8](repeating: 0, count: 8)
    var timeval = timeval(tv_sec: 1, tv_usec: 0)
    _ = setsockopt(
      extra, SOL_SOCKET, SO_RCVTIMEO, &timeval, socklen_t(MemoryLayout<timeval>.size))
    let result = recv(extra, &buffer, buffer.count, 0)
    #expect(result == 0 || result < 0)
  }
}

@Test func authorizedConnectionSurvivesSlowHandler() async throws {
  let path = "/tmp/aether-slow-\(UUID().uuidString.prefix(8)).sock"
  let server = AgentSocketServer(
    path: path, idleReadTimeoutMilliseconds: 200, acceptPollMilliseconds: 20)
  let store = AgentSessionStore(expectedToken: "secret")
  let task = Task.detached {
    try await server.run(authenticator: store) { _, request in
      try? await Task.sleep(for: .milliseconds(400))
      return AgentResponse(id: request.id, result: .object(["slow": .bool(true)]))
    }
  }
  defer { task.cancel() }
  try await waitForSocket(path)

  let client = AgentSocketClient(path: path, readTimeoutMilliseconds: 5_000)
  let response = try client.send(AgentRequest(method: .ping), token: "secret")
  #expect(response.error == nil)
  #expect(response.result?.object?["slow"]?.bool == true)
}

@Test func cookieBridgeRoundTripThroughDispatcherDoesNotCrash() async throws {
  let engine = NativeBrowserEngine()
  let dispatcher = AgentCommandDispatcher(engine: engine)
  let created = await dispatcher.handle(
    AgentRequest(method: .contextCreate, params: ["name": .string("cookie-regression")]))
  #expect(created.error == nil)
  let contextID = created.result?.object?["id"]?.number
  #expect(contextID != nil)
  guard let contextID else { return }

  let set = await dispatcher.handle(
    AgentRequest(
      method: .contextSetCookie,
      params: [
        "context": .number(contextID),
        "url": .string("https://cookies.regression.test"),
        "name": .string("session"),
        "value": .string("abc123"),
        "domain": .string("cookies.regression.test"),
        "path": .string("/"),
      ]))
  #expect(set.error == nil)

  let listed = await dispatcher.handle(
    AgentRequest(method: .contextCookies, params: ["context": .number(contextID)]))
  #expect(listed.error == nil)
  let cookies = listed.result?.array ?? []
  #expect(cookies.contains { cookie in
    cookie.object?["name"]?.string == "session" && cookie.object?["value"]?.string == "abc123"
  })

  let cleared = await dispatcher.handle(
    AgentRequest(
      method: .contextClearCookies, params: ["context": .number(contextID)]))
  #expect(cleared.error == nil)
}
