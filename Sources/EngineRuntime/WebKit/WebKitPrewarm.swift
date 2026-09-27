import AppKit
import Foundation
import WebKit

@MainActor
enum WebKitPrewarm {
  private static var profileWarmed: Set<ObjectIdentifier> = []

  /// Warms the WebContent process for the profile's real data store, so the
  /// first real tab reuses a live process instead of launching one. Loads
  /// only about:blank: no network traffic, no cookies sent anywhere.
  static func warmProfileStore(_ context: WebKitContext) {
    let id = ObjectIdentifier(context.store)
    guard !profileWarmed.contains(id) else { return }
    profileWarmed.insert(id)
    if profileWarmed.count > 8 { profileWarmed.removeFirst() }
    launchBlank(context: context)
  }

  private static func launchBlank(context: WebKitContext) {
    let configuration = WebKitPage.makeConfiguration(context: context)
    configuration.preferences.inactiveSchedulingPolicy = .none
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 16, height: 16), configuration: configuration)
    view.loadHTMLString("", baseURL: URL(string: "about:blank"))
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(30))
      view.stopLoading()
      view.removeFromSuperview()
    }
  }
}
