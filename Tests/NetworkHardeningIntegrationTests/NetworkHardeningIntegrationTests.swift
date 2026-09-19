import AetherNetworkHardening
import Foundation
import Testing

@Test func scriptResponseRejectsNosniffHTML() throws {
  #expect(throws: ResponseGuardError.nosniffBlocked) {
    try ResponseContentGuard.validate(
      status: 200,
      headers: ["Content-Type": "text/html", "X-Content-Type-Options": "nosniff"],
      destination: .script)
  }
}

@Test func stylesheetResponseRequiresCSSWithNosniff() throws {
  #expect(throws: ResponseGuardError.nosniffBlocked) {
    try ResponseContentGuard.validate(
      status: 200,
      headers: ["Content-Type": "text/javascript", "X-Content-Type-Options": "nosniff"],
      destination: .stylesheet)
  }
  try ResponseContentGuard.validate(
    status: 200,
    headers: ["Content-Type": "text/css; charset=utf-8", "X-Content-Type-Options": "nosniff"],
    destination: .stylesheet)
}

@Test func invalidSubresourceStatusIsRejected() throws {
  #expect(throws: ResponseGuardError.invalidStatus) {
    try ResponseContentGuard.validate(status: 404, headers: [:], destination: .script)
  }
}

@Test func hardenedNetworkCacheDoesNotReuseNoStore() {
  let policy = HTTPFreshness(headers: ["Cache-Control": "no-store, max-age=3600"])
  #expect(policy.storable == false)
}

@Test func HSTSUpgradesOnlyObservedHTTPSOrigins() async {
  let registry = HSTSRegistry()
  let target = URL(string: "http://a.example.test/path")!
  await registry.observe(
    url: URL(string: "http://example.test")!,
    headers: ["Strict-Transport-Security": "max-age=100; includeSubDomains"])
  #expect(await registry.upgrade(target) == target)
  await registry.observe(
    url: URL(string: "https://example.test")!,
    headers: ["Strict-Transport-Security": "max-age=100; includeSubDomains"])
  #expect(await registry.upgrade(target).scheme == "https")
}
