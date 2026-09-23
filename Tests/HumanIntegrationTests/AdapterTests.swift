import AetherHumanUI
import EngineCore
import Foundation
import Testing
@testable import AetherApp

@MainActor
@Test func nativeAdapterPreservesPageAndProfileIdentity() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let adapter = AetherEngineAdapter(profileDirectory: directory)
  let a = try await adapter.createPage(profileID: UUID())
  let b = try await adapter.createPage(profileID: UUID())
  #expect(a != b)
  #expect(adapter.surface(pageID: a) === adapter.surface(pageID: a))
  let pageA = try adapter.page(a)
  let pageB = try adapter.page(b)
  let contextA = try await adapter.engine.runtime.pageInfo(pageA).contextID
  let contextB = try await adapter.engine.runtime.pageInfo(pageB).contextID
  #expect(contextA != contextB)
  _ = try await adapter.engine.runtime.loadHTML(pageID: pageA,
    html: "<title>Connected</title><input id='field'><p>Actual engine</p>", url: URL(string: "https://fixture.test")!)
  #expect(try await adapter.snapshot(pageID: a).title == "Connected")
  #expect(try await adapter.engine.runtime.pageInfo(pageA).id.description == a)
  await adapter.close(pageID: a)
  await adapter.close(pageID: b)
  await adapter.shutdown()
}

@MainActor
@Test func adapterExposesRealPasskeyCapability() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let adapter = AetherEngineAdapter(profileDirectory: directory)
  let capability = adapter as any BrowserPasskeyCapability
  let state = capability.passkeyAuthorizationState()
  #expect(PasskeyAuthorizationState.allCases.contains(state))
  _ = capability.passkeyDeviceConfigured
  _ = capability.passkeyLocalAuthAvailable
  await adapter.shutdown()
}

@MainActor
@Test func disconnectedPortReportsNoPasskeyCapability() async {
  let port = DisconnectedEnginePort()
  #expect(port.passkeyDeviceConfigured == false)
  #expect(port.passkeyLocalAuthAvailable == false)
  #expect(port.passkeyAuthorizationState() == .unavailable)
  #expect(await port.requestPasskeyAuthorization() == .unavailable)
  #expect(await port.sessionState(pageID: "missing") == .notLoaded)
}

@MainActor
@Test func adapterSessionStateTracksUnknownPages() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let adapter = AetherEngineAdapter(profileDirectory: directory)
  #expect(await adapter.sessionState(pageID: "no-such-page") == .notLoaded)
  let pageID = try await adapter.createPage(profileID: UUID())
  #expect(EngineSessionState.allCases.contains(await adapter.sessionState(pageID: pageID)))
  await adapter.close(pageID: pageID)
  await adapter.shutdown()
}

@MainActor
@Test func unreachableExitFailsClosedWithoutLeaking() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let adapter = AetherEngineAdapter(profileDirectory: directory)
  let profileID = UUID()
  let route = BrowserNetworkRoute(region: .sanFrancisco, enabled: true, failClosed: true)
  let endpoint = RouteEndpoint(host: "127.0.0.1", port: 9, region: .sanFrancisco)
  #expect(
    try await adapter.applyNetworkRoute(profileID: profileID, route: route, endpoint: endpoint)
      == .blocked)
  #expect(adapter.observedExitIP(profileID: profileID) == nil)
  #expect(adapter.currentRouteStatus(profileID: profileID) == .blocked)
  await adapter.shutdown()
}
