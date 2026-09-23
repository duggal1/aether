import Foundation
import WebKit

enum WebKitAppearance {
  static let browserToken = "Version/\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).0 Safari/605.1.15"

  @MainActor static func install(in configuration: WKWebViewConfiguration) {
    configuration.applicationNameForUserAgent = browserToken
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
  }
}
