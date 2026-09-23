import AppKit
import Foundation
import WebKit

@MainActor
enum WebKitPrewarm {
  private static var warmed = false

  static func warmWebProcess() {
    guard !warmed else { return }
    warmed = true
    let configuration = WKWebViewConfiguration()
    WebKitAppearance.install(in: configuration)
    configuration.websiteDataStore = .nonPersistent()
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 16, height: 16), configuration: configuration)
    view.loadHTMLString("", baseURL: URL(string: "about:blank"))
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(30))
      view.stopLoading()
      view.removeFromSuperview()
    }
  }
}

extension BrowserRuntime {
  public func warmWebProcess() async {
    await MainActor.run { WebKitPrewarm.warmWebProcess() }
  }
}
