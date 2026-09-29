import Foundation
import Testing
import WebKit
@testable import EngineRuntime

/// Google serves its older results page to a user agent it doesn't recognise,
/// and WebKit's default carries no "Version/x Safari/x" token at all — so the
/// token is a behaviour, not a cosmetic string, and this is where it is kept.
@MainActor
@Test func pageConfigurationCarriesTheSafariUserAgent() {
  let configuration = WebKitPage.makeConfiguration(context: .ephemeral())
  #expect(configuration.applicationNameForUserAgent == WebKitUserAgent.safariToken)
  #expect(configuration.applicationNameForUserAgent?.hasPrefix("Version/") == true)
  #expect(configuration.applicationNameForUserAgent?.hasSuffix("Safari/605.1.15") == true)
}

@Test func safariTokenNamesAVersionAndSafariItself() {
  let token = WebKitUserAgent.safariToken
  let version = token.dropFirst("Version/".count).prefix { $0 != "." }
  #expect(Int(version) != nil)
  #expect((Int(version) ?? 0) >= 26)
  #expect(token.components(separatedBy: " ").count == 2)
}

/// The one that matters: whatever WebKit prints has to reach the page with a
/// Safari token in it, which is what a site reads before it decides which page
/// to serve.
@MainActor
@Test func thePageIsToldItIsSafari() async throws {
  let configuration = WebKitPage.makeConfiguration(context: .ephemeral())
  let webView = WKWebView(
    frame: NSRect(x: 0, y: 0, width: 32, height: 32), configuration: configuration)
  webView.loadHTMLString("<html></html>", baseURL: nil)
  var reported: String?
  for _ in 0..<40 where reported == nil {
    if let value = try? await webView.evaluateJavaScript("navigator.userAgent"),
      let text = value as? String
    {
      reported = text
      break
    }
    try? await Task.sleep(for: .milliseconds(50))
  }
  let userAgent = try #require(reported)
  #expect(userAgent.contains("AppleWebKit/605.1.15"))
  #expect(userAgent.contains("Version/"))
  #expect(userAgent.contains("Safari/605.1.15"))
}
