import Foundation

/// Redaction for layer 1 network evidence, applied at the producer (directive §7.2.5,
/// §11.3.4). A log that can leak a session token is a defect, not a feature, so the value
/// never enters the pipeline in the first place.
enum BrowserNetworkRedaction {
  private static let sensitiveKeys: Set<String> = [
    "password", "passwd", "pwd", "token", "access_token", "refresh_token", "id_token",
    "secret", "client_secret", "api_key", "apikey", "auth", "authorization", "session",
    "sessionid", "code",
  ]

  /// Removes userinfo and masks the values of sensitive query parameters. The URL itself is
  /// kept (evidence needs the origin and path), the secret inside it is not.
  static func redact(url raw: String) -> String {
    guard var components = URLComponents(string: raw) else { return raw }
    components.user = nil
    components.password = nil
    if let items = components.queryItems {
      components.queryItems = items.map { item in
        sensitiveKeys.contains(item.name.lowercased())
          ? URLQueryItem(name: item.name, value: "[redacted]")
          : item
      }
    }
    return components.string ?? raw
  }

  /// Redacts password/token-like fields in a bounded body snippet. The snippet is already
  /// bounded by the observer; this is the runtime's own, independent redaction and does not
  /// trust the page-side pass.
  static func redactBody(_ raw: String) -> String {
    var text = raw
    for key in sensitiveKeys {
      text = text.replacingOccurrences(
        of: "(?i)(\"\(key)\"\\s*:\\s*\")[^\"]*(\")", with: "$1[redacted]$2",
        options: .regularExpression)
      text = text.replacingOccurrences(
        of: "(?i)(^|[&?])\(key)=[^&]*", with: "$1\(key)=[redacted]",
        options: .regularExpression)
    }
    return text
  }
}
