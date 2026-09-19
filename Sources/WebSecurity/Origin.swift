import Foundation

public struct Origin: Hashable, Sendable, Codable, CustomStringConvertible {
  public var scheme: String
  public var host: String
  public var port: Int?
  public var isOpaque: Bool

  public init(scheme: String, host: String, port: Int? = nil) {
    self.scheme = scheme.lowercased()
    self.host = host.lowercased()
    self.port = port
    self.isOpaque = false
  }

  public init?(url: URL) {
    guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
      return nil
    }
    self.scheme = scheme
    self.host = host
    self.port = url.port
    self.isOpaque = false
  }

  public static let opaque = Origin(opaque: ())

  private init(opaque: Void) {
    self.scheme = "null"
    self.host = ""
    self.port = nil
    self.isOpaque = true
  }

  public var effectivePort: Int? {
    if let port { return port }
    if scheme == "http" { return 80 }
    if scheme == "https" { return 443 }
    if scheme == "ws" { return 80 }
    if scheme == "wss" { return 443 }
    return nil
  }

  public var description: String {
    if isOpaque { return "null" }
    if let port { return "\(scheme)://\(host):\(port)" }
    return "\(scheme)://\(host)"
  }

  public func isSameOrigin(as other: Origin) -> Bool {
    guard !isOpaque, !other.isOpaque else { return false }
    return scheme == other.scheme && host == other.host && effectivePort == other.effectivePort
  }

  public var isPotentiallyTrustworthy: Bool {
    if isOpaque { return false }
    if scheme == "https" || scheme == "wss" { return true }
    if host == "localhost" || host.hasSuffix(".localhost") { return true }
    if host == "127.0.0.1" || host == "[::1]" { return true }
    if scheme == "file" { return true }
    return false
  }

  public func isSameSite(as other: Origin) -> Bool {
    guard !isOpaque, !other.isOpaque else { return false }
    return scheme == other.scheme && registrableHost == other.registrableHost
  }

  public var registrableHost: String {
    let parts = host.split(separator: ".")
    guard parts.count >= 2 else { return host }
    return parts.suffix(2).joined(separator: ".")
  }
}
