import Foundation
import Synchronization

#if canImport(Darwin)
  import Darwin
  private let engineSocketStreamType = SOCK_STREAM
#elseif canImport(Glibc)
  import Glibc
  private let engineSocketStreamType = Int32(SOCK_STREAM.rawValue)
#endif

public enum AgentTransportError: Error, Sendable, CustomStringConvertible {
  case unsupported
  case socket(String)
  case protocolError(String)

  public var description: String {
    switch self {
    case .unsupported: return "Unix-domain sockets are unsupported on this platform"
    case .socket(let value): return value
    case .protocolError(let value): return value
    }
  }
}

public struct AgentSocketClient: Sendable {
  public let path: String
  public let readTimeoutMilliseconds: Int32
  public let writeTimeoutMilliseconds: Int32

  public init(
    path: String,
    readTimeoutMilliseconds: Int32 = 30_000,
    writeTimeoutMilliseconds: Int32 = 30_000
  ) {
    self.path = path
    self.readTimeoutMilliseconds = readTimeoutMilliseconds
    self.writeTimeoutMilliseconds = writeTimeoutMilliseconds
  }

  public func send(_ request: AgentRequest) throws -> AgentResponse {
    try withConnection { fd in
      try writeAll(fd: fd, data: AgentCodec.encode(request))
      let data = try readLine(fd: fd)
      return try AgentCodec.decodeResponse(data)
    }
  }

  public func send(_ request: AgentRequest, token: String) throws -> AgentResponse {
    try withConnection { fd in
      try writeAll(fd: fd, data: Data(token.utf8) + Data([0x0A]))
      let handshake = try readLine(fd: fd)
      let handshakeResponse = try AgentCodec.decodeResponse(handshake)
      if handshakeResponse.error != nil, handshakeResponse.id == "auth" {
        return handshakeResponse
      }
      try writeAll(fd: fd, data: AgentCodec.encode(request))
      let data = try readLine(fd: fd)
      return try AgentCodec.decodeResponse(data)
    }
  }

  private func withConnection(_ body: (Int32) throws -> AgentResponse) throws -> AgentResponse {
    #if canImport(Darwin) || canImport(Glibc)
      let fd = socket(AF_UNIX, engineSocketStreamType, 0)
      guard fd >= 0 else { throw AgentTransportError.socket("socket() failed") }
      defer { close(fd) }
      applySocketTimeouts(
        fd: fd,
        readMilliseconds: readTimeoutMilliseconds,
        writeMilliseconds: writeTimeoutMilliseconds)
      var address = try makeUnixAddress(path)
      let addressLength = unixAddressLength(address)
      let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, addressLength) }
      }
      guard result == 0 else { throw AgentTransportError.socket("connect() failed for \(path)") }
      return try body(fd)
    #else
      throw AgentTransportError.unsupported
    #endif
  }
}

final class SocketWorkerTable: @unchecked Sendable {
  private struct State {
    var stopped = false
    var clients: Set<Int32> = []
  }

  private let lock = Mutex<State>(State())

  var activeClientCount: Int {
    lock.withLock { $0.clients.count }
  }

  var stopped: Bool { lock.withLock { $0.stopped } }

  func insertClient(_ fd: Int32) {
    lock.withLock { state in
      state.clients.insert(fd)
      if state.stopped { _ = shutdown(fd, Int32(SHUT_RDWR)) }
    }
  }

  func removeClient(_ fd: Int32) {
    _ = lock.withLock { $0.clients.remove(fd) }
  }

  func interruptAll() {
    lock.withLock { state in
      state.stopped = true
      for fd in state.clients { _ = shutdown(fd, Int32(SHUT_RDWR)) }
    }
  }
}

public struct AgentSocketServer: Sendable {
  public let path: String
  public let maxConcurrentConnections: Int
  public let idleReadTimeoutMilliseconds: Int32
  public let writeTimeoutMilliseconds: Int32
  public let acceptPollMilliseconds: Int32

  public init(
    path: String,
    maxConcurrentConnections: Int = 64,
    idleReadTimeoutMilliseconds: Int32 = 60_000,
    writeTimeoutMilliseconds: Int32 = 30_000,
    acceptPollMilliseconds: Int32 = 100
  ) {
    self.path = path
    self.maxConcurrentConnections = max(1, maxConcurrentConnections)
    self.idleReadTimeoutMilliseconds = idleReadTimeoutMilliseconds
    self.writeTimeoutMilliseconds = writeTimeoutMilliseconds
    self.acceptPollMilliseconds = max(1, acceptPollMilliseconds)
  }

  public func run(handler: @escaping @Sendable (AgentRequest) async -> AgentResponse) async throws {
    #if canImport(Darwin) || canImport(Glibc)
      try await serve { table, client in
        Task.detached {
          defer {
            table.removeClient(client)
            close(client)
          }
          do {
            while true {
              let data = try await socketIO { try readLine(fd: client) }
              guard !data.isEmpty else { return }
              let response: AgentResponse
              do {
                let request = try AgentCodec.decodeRequest(data)
                response = await handler(request)
              } catch {
                response = AgentResponse(id: "unknown",
                  error: AgentError(code: "transport", message: String(describing: error)))
              }
              let encoded = try AgentCodec.encode(response)
              try await socketIO { try writeAll(fd: client, data: encoded) }
            }
          } catch {
            let response = AgentResponse(
              id: "unknown",
              error: AgentError(code: "transport", message: String(describing: error)))
            if let data = try? AgentCodec.encode(response) { try? await socketIO { try writeAll(fd: client, data: data) } }
          }
        }
      }
    #else
      throw AgentTransportError.unsupported
    #endif
  }

  public func run(
    authenticator: AgentSessionStore,
    handler: @escaping @Sendable (AgentPrincipal, AgentRequest) async -> AgentResponse
  ) async throws {
    #if canImport(Darwin) || canImport(Glibc)
      try await serve { table, client in
        Task.detached {
          defer {
            table.removeClient(client)
            close(client)
          }
          do {
            let tokenData = try await socketIO { try readLine(fd: client) }
            let presented = String(decoding: tokenData, as: UTF8.self)
            let principal: AgentPrincipal
            do {
              principal = try await authenticator.bind(presentedToken: presented)
            } catch {
              let rejection = AgentResponse(
                id: "auth",
                error: AgentError(code: "unauthorized", message: String(describing: error)))
              if let data = try? AgentCodec.encode(rejection) { try? await socketIO { try writeAll(fd: client, data: data) } }
              return
            }
            let acknowledgement = AgentResponse(
              id: "auth", result: .object(["principal": .string(principal.id)]))
            let encodedAcknowledgement = try AgentCodec.encode(acknowledgement)
            try await socketIO { try writeAll(fd: client, data: encodedAcknowledgement) }
            while true {
              let data = try await socketIO { try readLine(fd: client) }
              guard !data.isEmpty else { return }
              let response: AgentResponse
              do {
                let request = try AgentCodec.decodeRequest(data)
                response = await handler(principal, request)
              } catch {
                response = AgentResponse(
                  id: "unknown",
                  error: AgentError(code: "transport", message: String(describing: error)))
              }
              let encoded = try AgentCodec.encode(response)
              try await socketIO { try writeAll(fd: client, data: encoded) }
            }
          } catch {
            let response = AgentResponse(
              id: "unknown",
              error: AgentError(code: "transport", message: String(describing: error)))
            if let data = try? AgentCodec.encode(response) { try? await socketIO { try writeAll(fd: client, data: data) } }
          }
        }
      }
    #else
      throw AgentTransportError.unsupported
    #endif
  }

  #if canImport(Darwin) || canImport(Glibc)
    private func serve(
      spawn: @escaping @Sendable (SocketWorkerTable, Int32) -> Void
    ) async throws {
      let table = SocketWorkerTable()
      let lockFD = open(path + ".lock", O_CREAT | O_RDWR, mode_t(0o600))
      guard lockFD >= 0 else { throw AgentTransportError.socket("Cannot open socket lock for \(path)") }
      defer { close(lockFD) }
      guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
        throw AgentTransportError.socket("Socket already in use: \(path)")
      }
      _ = path.withCString { unlink($0) }
      let fd = socket(AF_UNIX, engineSocketStreamType, 0)
      guard fd >= 0 else { throw AgentTransportError.socket("socket() failed") }
      var address = try makeUnixAddress(path)
      let addressLength = unixAddressLength(address)
      let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, addressLength) }
      }
      guard bindResult == 0 else {
        close(fd)
        throw AgentTransportError.socket("bind() failed for \(path)")
      }
      guard chmod(path, mode_t(0o600)) == 0 else {
        close(fd)
        throw AgentTransportError.socket("chmod() failed for \(path)")
      }
      guard listen(fd, 128) == 0 else {
        close(fd)
        throw AgentTransportError.socket("listen() failed")
      }

      defer {
        table.interruptAll()
        close(fd)
        _ = path.withCString { unlink($0) }
      }

      try await withTaskCancellationHandler {
        try await socketIO {
          while !table.stopped {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, acceptPollMilliseconds)
            if ready < 0 {
              if errno == EINTR { continue }
              throw AgentTransportError.socket("poll() failed")
            }
            if ready == 0 { continue }
            if descriptor.revents & Int16(POLLIN) == 0 { continue }

            let client = accept(fd, nil, nil)
            if client < 0 {
              if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
              continue
            }
            if table.activeClientCount >= maxConcurrentConnections {
              close(client)
              continue
            }
            applySocketTimeouts(
              fd: client,
              readMilliseconds: idleReadTimeoutMilliseconds,
              writeMilliseconds: writeTimeoutMilliseconds)
            table.insertClient(client)
            spawn(table, client)
          }
        }
      } onCancel: {
        table.interruptAll()
      }
    }
  #endif
}

#if canImport(Darwin) || canImport(Glibc)
  private func makeUnixAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    #if canImport(Darwin)
      address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    #endif
    let bytes = Array(path.utf8CString)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard bytes.count <= capacity else {
      throw AgentTransportError.socket("Socket path is too long")
    }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
      raw.initializeMemory(as: UInt8.self, repeating: 0)
      for index in bytes.indices { raw[index] = UInt8(bitPattern: bytes[index]) }
    }
    return address
  }

  private func unixAddressLength(_ address: sockaddr_un) -> socklen_t {
    socklen_t(MemoryLayout<sockaddr_un>.size)
  }

  private func applySocketTimeouts(fd: Int32, readMilliseconds: Int32, writeMilliseconds: Int32) {
    var readTimeval = timeval(
      tv_sec: Int(readMilliseconds / 1000),
      tv_usec: suseconds_t((readMilliseconds % 1000) * 1000))
    _ = setsockopt(
      fd, SOL_SOCKET, SO_RCVTIMEO, &readTimeval, socklen_t(MemoryLayout<timeval>.size))
    var writeTimeval = timeval(
      tv_sec: Int(writeMilliseconds / 1000),
      tv_usec: suseconds_t((writeMilliseconds % 1000) * 1000))
    _ = setsockopt(
      fd, SOL_SOCKET, SO_SNDTIMEO, &writeTimeval, socklen_t(MemoryLayout<timeval>.size))
  }

  private func writeAll(fd: Int32, data: Data) throws {
    #if canImport(Darwin)
      var enabled: Int32 = 1
      guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled,
        socklen_t(MemoryLayout<Int32>.size)) == 0 else {
        throw AgentTransportError.socket("setsockopt(SO_NOSIGPIPE) failed")
      }
      let flags: Int32 = 0
    #else
      let flags = Int32(MSG_NOSIGNAL)
    #endif
    try data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      var sent = 0
      while sent < raw.count {
        let result = send(fd, base.advanced(by: sent), raw.count - sent, flags)
        if result < 0 {
          if errno == EINTR { continue }
          if errno == EAGAIN || errno == EWOULDBLOCK {
            throw AgentTransportError.protocolError("Write timed out")
          }
          throw AgentTransportError.socket("send() failed")
        }
        guard result > 0 else { throw AgentTransportError.socket("send() failed") }
        sent += result
      }
    }
  }

  private func readLine(fd: Int32, limit: Int = 8 * 1024 * 1024) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)
    while data.count < limit {
      let count = recv(fd, &buffer, min(buffer.count, limit - data.count), Int32(MSG_PEEK))
      if count < 0 {
        if errno == EINTR { continue }
        if errno == EAGAIN || errno == EWOULDBLOCK {
          throw AgentTransportError.protocolError("Read timed out")
        }
        throw AgentTransportError.socket("recv() failed")
      }
      if count == 0 {
        guard data.isEmpty else { throw AgentTransportError.protocolError("Incomplete message before disconnect") }
        return data
      }
      let newline = buffer[..<count].firstIndex(of: 0x0A)
      let needed = newline.map { $0 + 1 } ?? count
      let consumed = recv(fd, &buffer, needed, 0)
      if consumed < 0 {
        if errno == EINTR { continue }
        throw AgentTransportError.socket("recv() failed")
      }
      guard consumed > 0 else { throw AgentTransportError.protocolError("Connection closed during message") }
      if newline != nil, consumed == needed {
        data.append(contentsOf: buffer[..<(consumed - 1)])
        return data
      }
      data.append(contentsOf: buffer[..<consumed])
    }
    guard !data.isEmpty else {
      throw AgentTransportError.protocolError("Connection closed before a message was received")
    }
    guard data.count < limit else {
      throw AgentTransportError.protocolError("Message exceeded size limit")
    }
    return data
  }
#endif

private func socketIO<Value: Sendable>(
  _ operation: @escaping @Sendable () throws -> Value
) async throws -> Value {
  try await withCheckedThrowingContinuation { continuation in
    DispatchQueue.global(qos: .userInitiated).async {
      continuation.resume(with: Result(catching: operation))
    }
  }
}
