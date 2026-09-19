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
      try writeAll(fd: fd, data: AgentCodec.encode(request))
      let data = try readLine(fd: fd)
      return try AgentCodec.decodeResponse(data)
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
    try data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      var sent = 0
      while sent < raw.count {
        let result = send(fd, base.advanced(by: sent), raw.count - sent, 0)
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
