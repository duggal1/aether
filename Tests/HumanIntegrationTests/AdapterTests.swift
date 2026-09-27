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
@Test func legacyCredentialOriginNormalizationHandlesIPv6AndDefaultPorts() {
  #expect(AetherCredentialVault.origin(for: "http://[::1]:18771/login") == "http://[::1]:18771")
  #expect(AetherCredentialVault.origin(for: "https://example.test:443/login") == "https://example.test")
}

@MainActor
@Test func adapterMigratesLegacyHumanCredentialsIntoRuntimeVault() async throws {
  let profileID = UUID()
  let origin = "https://credential-migration-\(UUID().uuidString.lowercased()).test"
  #expect(AetherCredentialVault.save(
    profileID: profileID, origin: origin, username: "person", password: "legacy-secret"))
  let legacy = try #require(AetherCredentialVault.saved(profileID: profileID).first)
  defer { _ = AetherCredentialVault.delete(legacy) }
  #expect(AetherCredentialVault.credentials(profileID: profileID, origin: origin).count == 1)

  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let adapter = AetherEngineAdapter(profileDirectory: directory)
  let contextID = try await adapter.context(for: profileID)
  let credentials = try await adapter.savedCredentials(profileID: profileID, origin: origin)
  let profileCredentials = try await adapter.engine.runtime.listCredentials(contextID: contextID)
  #expect(profileCredentials.count == 1)
  #expect(profileCredentials.first?.profileID == profileID.uuidString)
  #expect(profileCredentials.first?.origin == origin)
  let credential = try #require(credentials.first)
  #expect(credentials.count == 1)
  #expect(credential.username == "person")
  #expect(credential.profileID == profileID)
  #expect(AetherCredentialVault.saved(profileID: profileID).isEmpty)

  let secret = try await adapter.engine.runtime.credentialSecret(
    contextID: contextID, credentialID: credential.id)
  #expect(secret.password == "legacy-secret")

  try await adapter.saveCredential(
    profileID: profileID, origin: origin, username: "person", password: "rotated-secret")
  let updated = try await adapter.savedCredentials(profileID: profileID, origin: origin)
  #expect(updated.count == 1)
  #expect(updated[0].id == credential.id)
  #expect(
    try await adapter.engine.runtime.credentialSecret(
      contextID: contextID, credentialID: credential.id).password == "rotated-secret")

  try await adapter.deleteCredential(profileID: profileID, credentialID: credential.id)
  #expect(try await adapter.savedCredentials(profileID: profileID, origin: origin).isEmpty)
  try await adapter.engine.destroyContext(contextID)
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
