import EngineCore
import Foundation
import Testing
import WebKit
@testable import EngineRuntime

struct WebKitContentBlockerTests {
  @MainActor
  private static func webKitCompile(_ json: String, identifier: String) async throws {
    guard let store = WKContentRuleListStore.default() else {
      throw BrowserRuntimeError.invalidState("Content rule store is unavailable")
    }
    try? await store.removeContentRuleList(forIdentifier: identifier)
    _ = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
    let lookedUp: WKContentRuleList? = try await withCheckedThrowingContinuation { continuation in
      store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
        continuation.resume(returning: list)
      }
    }
    guard lookedUp != nil else {
      throw BrowserRuntimeError.invalidState("Compiled rule list was not retrievable")
    }
    try? await store.removeContentRuleList(forIdentifier: identifier)
  }

  @Test @MainActor func defaultAppRuleListCompilesInWebKit() async throws {
    let source = AggressiveBlockFilter.ruleList(
      blockAds: true, blockTrackers: true, hideIP: false, cookieBanners: true)
    let json = try AggressiveBlockFilter.compile(source: source)
    let decoded = try JSONDecoder().decode([[String: [String: String]]].self, from: Data(json.utf8))
    #expect(decoded.count > 200)
    try await Self.webKitCompile(json, identifier: "aether-test-default-app-list")
  }

  @Test @MainActor func trackerHostsCompileAsCookieBlocks() async throws {
    let source = AggressiveBlockFilter.ruleList(
      blockAds: false, blockTrackers: true, hideIP: false, cookieBanners: false)
    let json = try AggressiveBlockFilter.compile(source: source)
    try await Self.webKitCompile(json, identifier: "aether-test-cookie-list")
  }

  @Test @MainActor func hideIPRuleListCompilesInWebKit() async throws {
    let source = AggressiveBlockFilter.ruleList(
      blockAds: true, blockTrackers: true, hideIP: true, cookieBanners: true)
    let json = try AggressiveBlockFilter.compile(source: source)
    try await Self.webKitCompile(json, identifier: "aether-test-hideip-list")
  }
}
