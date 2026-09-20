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
