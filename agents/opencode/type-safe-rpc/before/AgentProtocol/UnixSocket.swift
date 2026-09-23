import Foundation

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

  public init(path: String) {
    self.path = path
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

public struct AgentSocketServer: Sendable {
  public let path: String

  public init(path: String) {
    self.path = path
  }

  public func run(handler: @escaping @Sendable (AgentRequest) async -> AgentResponse) async throws {
    #if canImport(Darwin) || canImport(Glibc)
      _ = path.withCString { unlink($0) }
      let fd = socket(AF_UNIX, engineSocketStreamType, 0)
      guard fd >= 0 else { throw AgentTransportError.socket("socket() failed") }
      defer {
        close(fd)
        _ = path.withCString { unlink($0) }
      }
      var address = try makeUnixAddress(path)
      let addressLength = unixAddressLength(address)
      let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, addressLength) }
      }
      guard bindResult == 0 else { throw AgentTransportError.socket("bind() failed for \(path)") }
      guard chmod(path, mode_t(0o600)) == 0 else {
        throw AgentTransportError.socket("chmod() failed for \(path)")
      }
      guard listen(fd, 128) == 0 else { throw AgentTransportError.socket("listen() failed") }

      while !Task.isCancelled {
        let client = accept(fd, nil, nil)
        if client < 0 { continue }
        Task.detached {
          defer { close(client) }
          do {
            let data = try readLine(fd: client)
            let request = try AgentCodec.decodeRequest(data)
            let response = await handler(request)
            try writeAll(fd: client, data: AgentCodec.encode(response))
          } catch {
            let response = AgentResponse(
              id: "unknown",
              error: AgentError(code: "transport", message: String(describing: error)))
            if let data = try? AgentCodec.encode(response) { try? writeAll(fd: client, data: data) }
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
      try await runSocket { client in
        do {
          let tokenData = try readLine(fd: client)
          let presented = String(decoding: tokenData, as: UTF8.self)
          let principal: AgentPrincipal
          do {
            principal = try await authenticator.bind(presentedToken: presented)
          } catch {
            let rejection = AgentResponse(
              id: "auth",
              error: AgentError(code: "unauthorized", message: String(describing: error)))
            if let data = try? AgentCodec.encode(rejection) { try? writeAll(fd: client, data: data) }
            return
          }
          let acknowledgement = AgentResponse(
            id: "auth", result: .object(["principal": .string(principal.id)]))
          try writeAll(fd: client, data: AgentCodec.encode(acknowledgement))
          while true {
            let data = try readLine(fd: client)
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
            try writeAll(fd: client, data: AgentCodec.encode(response))
          }
        } catch {
          let response = AgentResponse(
            id: "unknown",
            error: AgentError(code: "transport", message: String(describing: error)))
          if let data = try? AgentCodec.encode(response) { try? writeAll(fd: client, data: data) }
        }
      }
    #else
      throw AgentTransportError.unsupported
    #endif
  }

  private func runSocket(
    _ clientBody: @escaping @Sendable (Int32) async -> Void
  ) async throws {
    #if canImport(Darwin) || canImport(Glibc)
      _ = path.withCString { unlink($0) }
      let fd = socket(AF_UNIX, engineSocketStreamType, 0)
      guard fd >= 0 else { throw AgentTransportError.socket("socket() failed") }
      defer {
        close(fd)
        _ = path.withCString { unlink($0) }
      }
      var address = try makeUnixAddress(path)
      let addressLength = unixAddressLength(address)
      let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, addressLength) }
      }
      guard bindResult == 0 else { throw AgentTransportError.socket("bind() failed for \(path)") }
      guard chmod(path, mode_t(0o600)) == 0 else {
        throw AgentTransportError.socket("chmod() failed for \(path)")
      }
      guard listen(fd, 128) == 0 else { throw AgentTransportError.socket("listen() failed") }

      while !Task.isCancelled {
        let client = accept(fd, nil, nil)
        if client < 0 { continue }
        Task.detached {
          defer { close(client) }
          await clientBody(client)
        }
      }
    #else
      throw AgentTransportError.unsupported
    #endif
  }
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
        guard result > 0 else { throw AgentTransportError.socket("send() failed") }
        sent += result
      }
    }
  }

  private func readLine(fd: Int32, limit: Int = 8 * 1024 * 1024) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)
    while data.count < limit {
      let count = recv(fd, &buffer, buffer.count, 0)
      if count < 0 { throw AgentTransportError.socket("recv() failed") }
      if count == 0 { break }
      if let newline = buffer[..<count].firstIndex(of: 0x0A) {
        data.append(contentsOf: buffer[..<newline])
        return data
      }
      data.append(contentsOf: buffer[..<count])
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
