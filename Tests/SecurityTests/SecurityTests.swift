import Foundation
import WebSecurity
import Testing

@Test func originComparisonUsesEffectivePorts() {
  let a = Origin(url: URL(string: "https://example.com/path")!)!
  let b = Origin(url: URL(string: "https://example.com:443/other")!)!
  let c = Origin(url: URL(string: "http://example.com")!)!
  #expect(a.isSameOrigin(as: b))
  #expect(!a.isSameOrigin(as: c))
}

@Test func permissionStoreSnapshotsRestore() async {
  let store = PermissionStore()
  let origin = Origin(url: URL(string: "https://example.com")!)!
  await store.set(.deny, for: .camera, origin: origin)
  let snapshot = await store.snapshot()
  let restored = PermissionStore()
  await restored.restore(snapshot)
  #expect(await restored.decision(for: .camera, origin: origin) == .deny)
  #expect(await restored.decision(for: .microphone, origin: origin) == .prompt)
}

@Test func corsAllowsListedOrigin() {
  let origin = Origin(url: URL(string: "https://app.example")!)!
  #expect(
    CORSPolicy.checkResponse(
      requestOrigin: origin,
      responseHeaders: ["Access-Control-Allow-Origin": "https://app.example"],
      allowsCredentials: false) == .allow)
  #expect(
    CORSPolicy.checkResponse(
      requestOrigin: origin, responseHeaders: ["Access-Control-Allow-Origin": "*"],
      allowsCredentials: true) != .allow)
  #expect(
    CORSPolicy.checkResponse(
      requestOrigin: origin, responseHeaders: [:], allowsCredentials: false) != .allow)
}

@Test func cspBlocksInlineByDefault() {
  let policy = ContentSecurityPolicy.parse("default-src 'self'")
  let origin = Origin(url: URL(string: "https://app.example")!)!
  #expect(!policy.allowsScript(origin: origin, source: nil, inline: true))
  #expect(
    policy.allowsScript(
      origin: origin, source: URL(string: "https://app.example/x.js"), inline: false))
  #expect(
    !policy.allowsScript(
      origin: origin, source: URL(string: "https://evil.test/x.js"), inline: false))
  #expect(
    ContentSecurityPolicy.parse("script-src 'none'")
      .allowsScript(origin: origin, source: URL(string: "https://app.example/x.js"), inline: false)
      == false)
}

@Test func navigationPolicyDeniesDangerousTargets() {
  #expect(
    NavigationPolicy.decideNavigation(from: nil, to: URL(string: "javascript:alert(1)")!)
      == .deny("javascript: navigation is not executed"))
  #expect(
    NavigationPolicy.decideNavigation(from: nil, to: URL(string: "https://example.com/")!)
      == .allow)
  #expect(
    MixedContent.decision(
      pageURL: URL(string: "https://example.com/")!,
      resourceURL: URL(string: "http://example.com/x.js")!) == .block)
  #expect(
    MixedContent.decision(
      pageURL: URL(string: "https://example.com/")!,
      resourceURL: URL(string: "https://example.com/x.js")!) == .allow)
}

@Test func permissionBoundaryRequiresTrustworthyTopLevel() {
  let secure = Origin(url: URL(string: "https://example.com")!)!
  let plain = Origin(url: URL(string: "http://example.com")!)!
  #expect(PermissionBoundary.allows(.camera, origin: secure, isTopLevel: true))
  #expect(!PermissionBoundary.allows(.camera, origin: secure, isTopLevel: false))
  #expect(!PermissionBoundary.allows(.camera, origin: plain, isTopLevel: true))
}
