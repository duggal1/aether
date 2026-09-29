import Foundation

/// The browser's own user agent, as the tail Safari puts on its own.
///
/// WebKit's default user agent stops at "AppleWebKit/605.1.15 (KHTML, like
/// Gecko)" — there is no "Version/x Safari/x" token in it — and a site that
/// reads the user agent takes the browser for one it has never seen. Google is
/// where that shows: an unrecognised browser is served its older results page,
/// with none of the current search experience. The version is Safari's own, and
/// Safari's major tracks the macOS major.
enum WebKitUserAgent {
  static let safariToken =
    "Version/\(max(26, ProcessInfo.processInfo.operatingSystemVersion.majorVersion)).0 Safari/605.1.15"
}
