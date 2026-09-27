import Foundation
import WebKit

enum WebKitAppearance {
  @MainActor static func install(in configuration: WKWebViewConfiguration) {
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.suppressesIncrementalRendering = false
    configuration.upgradeKnownHostsToHTTPS = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
  }
}
