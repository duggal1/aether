import Foundation

public struct ContentSecurityPolicy: Hashable, Sendable {
  public var directives: [String: [String]]

  public init(directives: [String: [String]] = [:]) {
    self.directives = directives
  }

  public static func parse(_ source: String) -> ContentSecurityPolicy {
    var directives: [String: [String]] = [:]
    for part in source.split(separator: ";") {
      let tokens = part.split(whereSeparator: { $0.isWhitespace }).map(String.init)
      guard let first = tokens.first else { continue }
      directives[first.lowercased()] = Array(tokens.dropFirst())
    }
    return ContentSecurityPolicy(directives: directives)
  }

  public static func parse(headers: [String: String]) -> ContentSecurityPolicy? {
    let lowered = Dictionary(
      uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
    if let value = lowered["content-security-policy"] { return parse(value) }
    return nil
  }

  public func allowsScript(origin: Origin, source: URL?, inline: Bool) -> Bool {
    check(directive: "script-src", fallback: "default-src", origin: origin, source: source, inline: inline)
  }

  public func allowsStyle(origin: Origin, source: URL?, inline: Bool) -> Bool {
    check(directive: "style-src", fallback: "default-src", origin: origin, source: source, inline: inline)
  }

  public func allowsImage(origin: Origin, source: URL?) -> Bool {
    check(directive: "img-src", fallback: "default-src", origin: origin, source: source, inline: false)
  }

  public func allowsConnect(origin: Origin, source: URL?) -> Bool {
    check(directive: "connect-src", fallback: "default-src", origin: origin, source: source, inline: false)
  }

  public func allowsFrame(origin: Origin, source: URL?) -> Bool {
    check(
      directive: "frame-src", fallback: "child-src", origin: origin, source: source, inline: false,
      secondFallback: "default-src")
  }

  func check(
    directive: String, fallback: String, origin: Origin, source: URL?, inline: Bool,
    secondFallback: String? = nil
  ) -> Bool {
    let list: [String]?
    if let exact = directives[directive] {
      list = exact
    } else if let first = directives[fallback] {
      list = first
    } else if let second = secondFallback, let value = directives[second] {
      list = value
    } else {
      return true
    }
    guard let list else { return true }
    if list.contains("'none'") { return false }
    if inline {
      return list.contains("'unsafe-inline'")
    }
    guard let source else { return false }
    return matchesSource(source, allowlist: list, pageOrigin: origin)
  }

  func matchesSource(_ url: URL, allowlist: [String], pageOrigin: Origin) -> Bool {
    for entry in allowlist {
      if entry == "'self'" {
        if let urlOrigin = Origin(url: url), urlOrigin.isSameOrigin(as: pageOrigin) {
          return true
        }
        continue
      }
      if entry == "*" {
        if ["http", "https", "ws", "wss"].contains(url.scheme?.lowercased()) { return true }
        continue
      }
      if entry.hasSuffix(":") {
        if url.scheme?.lowercased() == entry.dropLast().lowercased() { return true }
        continue
      }
      if entry.contains("://") {
        if matchHostPattern(entry, url: url) { return true }
        continue
      }
      if entry.hasPrefix("*.") {
        let suffix = entry.dropFirst(2).lowercased()
        if let host = url.host?.lowercased(), host == suffix || host.hasSuffix("." + suffix) {
          return true
        }
        continue
      }
      if let host = url.host?.lowercased(), host == entry.lowercased() { return true }
    }
    return false
  }

  func matchHostPattern(_ pattern: String, url: URL) -> Bool {
    let parts = pattern.split(separator: ":", maxSplits: 1).map(String.init)
    let authority = parts[0].lowercased()
    let scheme = url.scheme?.lowercased()
    if authority.contains("://") {
      let halves = authority.split(separator: "/", maxSplits: 1).map(String.init)
      guard halves.count == 2, halves[0] == scheme else { return false }
      return hostMatches(halves[1], url: url)
    }
    return hostMatches(authority, url: url)
  }

  func hostMatches(_ pattern: String, url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    if pattern.hasPrefix("*.") {
      let suffix = String(pattern.dropFirst(2))
      return host == suffix || host.hasSuffix("." + suffix)
    }
    return host == pattern
  }
}
