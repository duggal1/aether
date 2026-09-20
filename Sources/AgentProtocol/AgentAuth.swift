import Foundation

#if canImport(Darwin)
  import Security
#endif

public struct AgentPrincipal: Hashable, Sendable, Codable {
  public enum Kind: String, Sendable, Codable {
    case host
    case agent
  }

  public let id: String
  public let kind: Kind

  public init(id: String, kind: Kind) {
    self.id = id
    self.kind = kind
  }

  public static let host = AgentPrincipal(id: "host", kind: .host)
  public var isHost: Bool { kind == .host }
}

public enum AgentAuthError: Error, Sendable, CustomStringConvertible {
  case unauthorized
  case lockedOut
  case tokenFileUnreadable(String)

  public var description: String {
    switch self {
    case .unauthorized: return "authentication failed: invalid or missing token"
    case .lockedOut: return "authentication locked out after repeated failures"
    case .tokenFileUnreadable(let path): return "token file unreadable: \(path)"
    }
  }
}

public enum AgentAuth {
  public static let tokenLengthBytes = 32

  public static func generateToken() -> String {
    var bytes = [UInt8](repeating: 0, count: tokenLengthBytes)
    #if canImport(Darwin)
      let status = SecRandomCopyBytes(kSecRandomDefault, tokenLengthBytes, &bytes)
      if status != errSecSuccess {
        fillWithSystemRandom(&bytes)
      }
    #else
      fillWithSystemRandom(&bytes)
    #endif
    return bytes.map { String(format: "%02x", $0) }.joined()
  }

  private static func fillWithSystemRandom(_ bytes: inout [UInt8]) {
    var generator = SystemRandomNumberGenerator()
    for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max, using: &generator) }
  }

  public static func writeTokenFile(_ token: String, to path: String) throws {
    let data = Data(token.utf8)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    #if canImport(Darwin)
      guard chmod(path, mode_t(0o600)) == 0 else {
        throw AgentAuthError.tokenFileUnreadable(path)
      }
    #else
      _ = path
    #endif
  }

  public static func readTokenFile(from path: String) throws -> String {
    let raw = try String(contentsOfFile: path, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { throw AgentAuthError.tokenFileUnreadable(path) }
    return raw
  }

  public static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
    let left = Array(a.utf8)
    let right = Array(b.utf8)
    guard left.count == right.count else { return false }
    var difference: UInt8 = 0
    for index in left.indices { difference |= left[index] ^ right[index] }
    return difference == 0
  }
}

public actor AgentSessionStore {
  public nonisolated let principal = AgentPrincipal(id: UUID().uuidString, kind: .agent)
  private let expectedToken: String
  private let maximumFailedAttempts: Int
  private var failedAttempts = 0
  private var lockedOut = false
  private var issuedPrincipals: Set<String> = []

  public init(expectedToken: String, maximumFailedAttempts: Int = 5) {
    self.expectedToken = expectedToken
    self.maximumFailedAttempts = maximumFailedAttempts
  }

  public func bind(presentedToken: String) throws -> AgentPrincipal {
    if lockedOut { throw AgentAuthError.lockedOut }
    guard AgentAuth.constantTimeEqual(presentedToken, expectedToken) else {
      failedAttempts += 1
      if failedAttempts >= maximumFailedAttempts { lockedOut = true }
      throw AgentAuthError.unauthorized
    }
    failedAttempts = 0
    issuedPrincipals.insert(principal.id)
    return principal
  }

  public func hasIssued(_ id: String) -> Bool {
    issuedPrincipals.contains(id)
  }

  public func issuedCount() -> Int {
    issuedPrincipals.count
  }
}
