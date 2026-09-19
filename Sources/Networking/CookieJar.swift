import Foundation
import Synchronization

public struct Cookie: Hashable, Sendable, Codable {
  public var name: String
  public var value: String
  public var domain: String
  public var path: String
  public var expires: Date?
  public var secure: Bool
  public var httpOnly: Bool
  public var sameSite: String?
  public var hostOnly: Bool

  public init(
    name: String, value: String, domain: String, path: String = "/", expires: Date? = nil,
    secure: Bool = false, httpOnly: Bool = false, sameSite: String? = nil,
    hostOnly: Bool = true
  ) {
    self.name = name
    self.value = value
    self.domain = domain.lowercased()
    self.path = path.isEmpty ? "/" : path
    self.expires = expires
    self.secure = secure
    self.httpOnly = httpOnly
    self.sameSite = sameSite
    self.hostOnly = hostOnly
  }

  public var sameSitePolicy: SameSitePolicy {
    SameSitePolicy(rawValue: sameSite?.lowercased() ?? "lax") ?? .lax
  }
}

public enum SameSitePolicy: String, Hashable, Sendable {
  case strict
  case lax
  case none
}

public struct CookieRequestContext: Hashable, Sendable {
  public var topLevelHost: String?
  public var method: String
  public var isTopLevelNavigation: Bool

  public init(
    topLevelHost: String? = nil, method: String = "GET", isTopLevelNavigation: Bool = false
  ) {
    self.topLevelHost = topLevelHost?.lowercased()
    self.method = method.uppercased()
    self.isTopLevelNavigation = isTopLevelNavigation
  }
}

public final class CookieJar: @unchecked Sendable {
  private struct State: Sendable {
    var cookies: [String: Cookie] = [:]
  }

  private let state: Mutex<State>

  public init() {
    state = Mutex(State())
  }

  public func header(for url: URL, now: Date = Date()) -> String? {
    header(for: url, context: nil, now: now)
  }

  public func scriptVisibleHeader(for url: URL, now: Date = Date()) -> String? {
    state.withLock { state in
      purgeExpired(now: now, state: &state)
      guard let host = url.host?.lowercased() else { return nil }
      let path = url.path.isEmpty ? "/" : url.path
      let secure = url.scheme?.lowercased() == "https"
      let matched = state.cookies.values.filter { cookie in
        !cookie.httpOnly && Self.domainMatches(host: host, cookie: cookie)
          && path.hasPrefix(cookie.path)
          && (!cookie.secure || secure)
          && Self.sameSiteAllows(cookie: cookie, host: host, context: nil)
      }.sorted { $0.path.count > $1.path.count }
      guard !matched.isEmpty else { return nil }
      return matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
  }

  public func header(for url: URL, context: CookieRequestContext?, now: Date = Date()) -> String? {
    state.withLock { state in
      purgeExpired(now: now, state: &state)
      guard let host = url.host?.lowercased() else { return nil }
      let path = url.path.isEmpty ? "/" : url.path
      let secure = url.scheme?.lowercased() == "https"
      let matched = state.cookies.values.filter { cookie in
        Self.domainMatches(host: host, cookie: cookie) && path.hasPrefix(cookie.path)
          && (!cookie.secure || secure)
          && Self.sameSiteAllows(cookie: cookie, host: host, context: context)
      }.sorted { $0.path.count > $1.path.count }
      guard !matched.isEmpty else { return nil }
      return matched.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
  }

  public func absorb(setCookie: String, from url: URL) {
    absorb(
      setCookie: setCookie, from: url,
      isSecureTransport: url.scheme?.lowercased() == "https")
  }

  public func setFromScript(_ value: String, from url: URL) {
    absorb(setCookie: value, from: url,
      isSecureTransport: url.scheme?.lowercased() == "https", fromScript: true)
  }

  public func absorb(
    setCookie: String, from url: URL, isSecureTransport: Bool, fromScript: Bool = false
  ) {
    guard let host = url.host?.lowercased() else { return }
    let segments = setCookie.split(separator: ";", omittingEmptySubsequences: true).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let first = segments.first else { return }
    let pair = first.split(separator: "=", maxSplits: 1).map(String.init)
    guard pair.count == 2, !pair[0].isEmpty else { return }
    let cookieName = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cookieName.isEmpty else { return }

    var cookie = Cookie(
      name: cookieName, value: pair[1], domain: host, path: Self.defaultPath(for: url))
    var sawDomain = false
    var sawMaxAge = false
    var maxAgeInvalid = false
    for segment in segments.dropFirst() {
      let parts = segment.split(separator: "=", maxSplits: 1).map(String.init)
      let name = parts[0].lowercased()
      let value = parts.count > 1 ? parts[1] : ""
      switch name {
      case "domain":
        let candidate = value.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard !candidate.isEmpty, Self.domainAttributeAccepts(host: host, domain: candidate) else {
          return
        }
        cookie.domain = candidate
        cookie.hostOnly = false
        sawDomain = true
      case "path":
        cookie.path = value.hasPrefix("/") ? value : Self.defaultPath(for: url)
      case "secure": cookie.secure = true
      case "httponly": cookie.httpOnly = true
      case "samesite": cookie.sameSite = value.lowercased()
      case "max-age":
        sawMaxAge = true
        if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
          cookie.expires = Date().addingTimeInterval(seconds)
        } else {
          maxAgeInvalid = true
        }
      case "expires":
        if !sawMaxAge { cookie.expires = HTTPDateParser.parse(value) }
      default: break
      }
    }
    if maxAgeInvalid { cookie.expires = nil }
    if cookie.secure, !isSecureTransport { return }
    // HttpOnly is a network-only attribute. Script must neither create nor
    // replace a cookie protected by an HTTP Set-Cookie response.
    if fromScript && cookie.httpOnly { return }
    if cookieName.hasPrefix("__Secure-"), !cookie.secure { return }
    if cookieName.hasPrefix("__Host-") {
      if !cookie.secure || sawDomain || cookie.path != "/" { return }
      cookie.hostOnly = true
      cookie.domain = host
    }
    if cookie.sameSitePolicy == .none, !cookie.secure { return }
    state.withLock { state in
      if fromScript, let existing = state.cookies[Self.key(cookie)], existing.httpOnly {
        return
      }
      if cookie.value.isEmpty {
        if let expires = cookie.expires, expires <= Date() {
          state.cookies.removeValue(forKey: Self.key(cookie))
          return
        }
      }
      state.cookies[Self.key(cookie)] = cookie
    }
  }

  public func all() -> [Cookie] {
    state.withLock { state in
      purgeExpired(now: Date(), state: &state)
      return Array(state.cookies.values)
    }
  }

  public func remove(name: String, domain: String, path: String = "/") {
    state.withLock { state in
      state.cookies.removeValue(
        forKey: "\(domain.lowercased())|\(path.isEmpty ? "/" : path)|\(name)")
    }
  }

  public func store(_ cookie: Cookie) {
    state.withLock { state in
      var cookie = cookie
      cookie.domain = cookie.domain.lowercased()
      if cookie.path.isEmpty { cookie.path = "/" }
      state.cookies[Self.key(cookie)] = cookie
    }
  }

  public func clear() {
    state.withLock { $0.cookies.removeAll(keepingCapacity: false) }
  }

  private func purgeExpired(now: Date, state: inout State) {
    state.cookies = state.cookies.filter { _, cookie in cookie.expires.map { $0 > now } ?? true }
  }

  private static func domainMatches(host: String, cookie: Cookie) -> Bool {
    if cookie.hostOnly { return host == cookie.domain }
    return host == cookie.domain || host.hasSuffix("." + cookie.domain)
  }

  private static func domainAttributeAccepts(host: String, domain: String) -> Bool {
    if host == domain { return true }
    guard host.hasSuffix(domain), !host.dropLast(domain.count).isEmpty else { return false }
    let prefix = host.dropLast(domain.count)
    guard prefix.hasSuffix(".") else { return false }
    return domain.contains(".")
  }

  private static func sameSiteAllows(
    cookie: Cookie, host: String, context: CookieRequestContext?
  ) -> Bool {
    switch cookie.sameSitePolicy {
    case .strict:
      guard let context, let top = context.topLevelHost else { return true }
      return host == top
    case .lax:
      let top = context?.topLevelHost ?? host
      if host == top { return true }
      guard let context, context.isTopLevelNavigation, context.method == "GET" else {
        return false
      }
      return true
    case .none:
      return true
    }
  }

  private static func defaultPath(for url: URL) -> String {
    let path = url.path
    guard path.hasPrefix("/"), let slash = path.dropFirst().lastIndex(of: "/") else { return "/" }
    let prefix = path[..<slash]
    return prefix.isEmpty ? "/" : String(prefix)
  }

  private static func key(_ cookie: Cookie) -> String {
    "\(cookie.domain)|\(cookie.path)|\(cookie.name)"
  }
}

private enum HTTPDateParser {
  static func parse(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    for format in [
      "EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy",
    ] {
      formatter.dateFormat = format
      if let date = formatter.date(from: value) { return date }
    }
    return nil
  }
}
