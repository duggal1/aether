import Foundation

public enum CORSResult: Hashable, Sendable {
  case allow
  case deny(String)
}

public enum CORSPolicy {
  public static func checkResponse(
    requestOrigin: Origin?, responseHeaders: [String: String], allowsCredentials: Bool
  ) -> CORSResult {
    let headers = lowercased(responseHeaders)
    guard let allowOrigin = headers["access-control-allow-origin"] else {
      return .deny("missing access-control-allow-origin")
    }
    if allowOrigin == "*" {
      if allowsCredentials {
        return .deny("wildcard origin cannot satisfy credentialed requests")
      }
      return .allow
    }
    guard let requestOrigin else {
      return .deny("opaque request origin requires explicit allowlist match")
    }
    if allowOrigin == requestOrigin.description {
      return .allow
    }
    return .deny("origin \(requestOrigin) not allowlisted")
  }

  public static func checkPreflight(
    method: String, headers: [String], responseHeaders: [String: String]
  ) -> CORSResult {
    let response = lowercased(responseHeaders)
    if let allowMethods = response["access-control-allow-methods"] {
      let methods = allowMethods.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
      }
      if !methods.contains(method.uppercased()) && !methods.contains("*") {
        return .deny("method \(method) not preflight-allowlisted")
      }
    } else if !isSimpleMethod(method) {
      return .deny("non-simple method \(method) requires preflight allowlist")
    }
    if !headers.isEmpty {
      guard let allowHeaders = response["access-control-allow-headers"] else {
        return .deny("request headers require preflight allowlist")
      }
      let allowed = Set(
        allowHeaders.split(separator: ",").map {
          $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
      for header in headers {
        let name = header.lowercased()
        if isSimpleHeader(name) { continue }
        if !allowed.contains(name) && !allowed.contains("*") {
          return .deny("header \(header) not preflight-allowlisted")
        }
      }
    }
    return .allow
  }

  public static func isSimpleMethod(_ method: String) -> Bool {
    ["GET", "HEAD", "POST"].contains(method.uppercased())
  }

  public static func isSimpleHeader(_ name: String) -> Bool {
    ["accept", "accept-language", "content-language", "content-type"].contains(name.lowercased())
  }

  static func lowercased(_ headers: [String: String]) -> [String: String] {
    var result: [String: String] = [:]
    result.reserveCapacity(headers.count)
    for (key, value) in headers { result[key.lowercased()] = value }
    return result
  }
}
