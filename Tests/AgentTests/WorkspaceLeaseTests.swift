import AgentProtocol
import BrowserEngine
import BrowserEvents
import EngineCore
@testable import EngineRuntime
import Foundation
import Persistence
import Testing

@Test func workspaceLeaseLifecycleAndIsolation() async throws {
  let engine = NativeBrowserEngine()
  let firstContext = await engine.runtime.createContext(name: "worker-a")
  let secondContext = await engine.runtime.createContext(name: "worker-b")
  let firstProfile = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let secondProfile = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try await engine.runtime.openProfile(contextID: firstContext.id, directory: firstProfile)
  try await engine.runtime.openProfile(contextID: secondContext.id, directory: secondProfile)
  let events = await engine.runtime.observeEvents(
    filter: BrowserEventBus.Filter(families: [.lease]))
  var iterator = events.makeAsyncIterator()

  let lease = try await engine.runtime.acquireWorkspaceLease(
    contextID: firstContext.id, agentID: "worker-a", durationSeconds: 30,
    repositoryRoot: "/tmp/aether-repo", worktreePath: "/tmp/aether-repo/.worktrees/worker-a")
  #expect(lease.state == .active)
  #expect(lease.repositoryRoot == "/tmp/aether-repo")
  #expect(await iterator.next()?.name == "lease.acquired")

  await #expect(throws: BrowserRuntimeError.self) {
    try await engine.runtime.acquireWorkspaceLease(
      contextID: firstContext.id, agentID: "worker-b", durationSeconds: 30)
  }

  let renewed = try await engine.runtime.renewWorkspaceLease(
    contextID: firstContext.id, leaseID: lease.leaseID, agentID: "worker-a",
    durationSeconds: 60)
  #expect(renewed.expiresAt > lease.expiresAt)
  #expect(await iterator.next()?.name == "lease.renewed")

  let released = try await engine.runtime.releaseWorkspaceLease(
    contextID: firstContext.id, leaseID: lease.leaseID, agentID: "worker-a")
  #expect(released.state == .released)
  #expect(await iterator.next()?.name == "lease.released")

  let next = try await engine.runtime.acquireWorkspaceLease(
    contextID: firstContext.id, agentID: "worker-b", durationSeconds: 30)
  let other = try await engine.runtime.acquireWorkspaceLease(
    contextID: secondContext.id, agentID: "worker-b", durationSeconds: 30)
  #expect(next.workspaceID == lease.workspaceID)
  #expect(other.workspaceID != next.workspaceID)
  #expect(await engine.runtime.listWorkspaceLeases(contextID: secondContext.id).count == 1)

  _ = try await engine.runtime.cancelWorkspaceLease(
    contextID: firstContext.id, leaseID: next.leaseID)
  _ = try await engine.runtime.releaseWorkspaceLease(
    contextID: secondContext.id, leaseID: other.leaseID, agentID: "worker-b")
  try await engine.runtime.destroyContext(firstContext.id)
  try await engine.runtime.destroyContext(secondContext.id)
  try? FileManager.default.removeItem(at: firstProfile)
  try? FileManager.default.removeItem(at: secondProfile)
}

@Test func workspaceLeaseRecoversAgainstNewContextIdentity() async throws {
  let profile = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  let original = BrowserWorkspaceLease(
    workspaceID: UUID(), leaseID: UUID(), contextID: ContextID(rawValue: 777),
    agentID: "stable-worker", branchID: UUID().uuidString, repositoryRoot: nil,
    worktreePath: nil, acquiredAt: Date().timeIntervalSince1970,
    expiresAt: Date().timeIntervalSince1970 + 30, state: .active)
  let store = try ProfileStore.open(directory: profile)
  let savedRecord = WorkspaceLeaseRecord(info: original, runtimeID: UUID())
  try store.setKV(
    scope: "workspace", key: "lease.v1", value: try JSONEncoder().encode(savedRecord))
  store.close()

  let restartedRuntime = BrowserRuntime()
  let restoredContext = await restartedRuntime.createContext(name: "recover")
  try await restartedRuntime.openProfile(contextID: restoredContext.id, directory: profile)
  let recovered = await restartedRuntime.workspaceLease(contextID: restoredContext.id)
  #expect(recovered?.state == .recoverable)
  #expect(recovered?.contextID == restoredContext.id)
  #expect(recovered?.contextID != original.contextID)

  let resumed = try await restartedRuntime.acquireWorkspaceLease(
    contextID: restoredContext.id, agentID: "stable-worker", durationSeconds: 30)
  #expect(resumed.workspaceID == original.workspaceID)
  #expect(resumed.leaseID != original.leaseID)
  _ = try await restartedRuntime.releaseWorkspaceLease(
    contextID: restoredContext.id, leaseID: resumed.leaseID, agentID: "stable-worker")
  try await restartedRuntime.destroyContext(restoredContext.id)
  try? FileManager.default.removeItem(at: profile)
}

@Test func expiredLeaseFreezesItsLiveWebKitPageAndPublishesExpiry() async throws {
  let runtime = BrowserRuntime()
  let context = await runtime.createContext(name: "expiring-worker")
  let profile = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: profile) }
  try await runtime.openProfile(contextID: context.id, directory: profile)
  let page = try await runtime.createPage(contextID: context.id)
  _ = try await runtime.loadHTML(
    pageID: page.id,
    html: "<html><head><title>Lease expiry</title></head><body>ready</body></html>",
    url: URL(string: "https://example.test/lease")!)
  let stream = await runtime.observeEvents(
    filter: BrowserEventBus.Filter(families: [.lease]))
  var events = stream.makeAsyncIterator()
  let lease = try await runtime.acquireWorkspaceLease(
    contextID: context.id, agentID: "expiring-worker", durationSeconds: 1)
  #expect(await events.next()?.name == "lease.acquired")

  try await Task.sleep(for: .milliseconds(1_300))
  let expired = await runtime.workspaceLease(contextID: context.id)
  #expect(expired?.leaseID == lease.leaseID)
  #expect(expired?.state == .expired)
  #expect(try await runtime.lifecycleState(pageID: page.id) == .frozen)
  let expiryEvent = await events.next()
  #expect(expiryEvent?.name == "lease.expired")
  #expect(expiryEvent?.identity.context == context.id)
  #expect(expiryEvent?.identity.branch == nil)
}

@Test func authenticatedWorkspaceLeaseChecksPrincipalAndIgnoresAgentIDSpoofing() async throws {
  let engine = NativeBrowserEngine()
  let dispatcher = AgentCommandDispatcher(engine: engine)
  let ownership = AgentOwnershipRegistry()
  let principalA = AgentPrincipal(id: "worker-a-principal", kind: .agent)
  let principalB = AgentPrincipal(id: "worker-b-principal", kind: .agent)
  let created = await dispatcher.handle(
    AgentRequest(method: .contextCreate, params: ["name": .string("leased")]),
    principal: principalA, ownership: ownership)
  let contextValue = try #require(created.result?.object?["id"]?.exactUInt64)
  let profile = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: profile) }
  let opened = await dispatcher.handle(
    AgentRequest(
      method: "context.openProfile",
      params: ["context": .uint(contextValue), "directory": .string(profile.path)]))
  #expect(opened.error == nil)

  let acquired = await dispatcher.handle(
    AgentRequest(
      method: .workspaceLeaseAcquire,
      params: [
        "context": .uint(contextValue), "agentID": .string("spoofed-agent"),
        "leaseSeconds": .number(30),
      ]),
    principal: principalA, ownership: ownership)
  #expect(acquired.error == nil)
  #expect(acquired.result?.object?["agentID"]?.string == principalA.id)

  let denied = await dispatcher.handle(
    AgentRequest(
      method: .workspaceLeaseList, params: ["context": .uint(contextValue)]),
    principal: principalB, ownership: ownership)
  #expect(denied.error?.code == "unauthorized")

  let destroyed = await dispatcher.handle(
    AgentRequest(method: .contextDestroy, params: ["context": .uint(contextValue)]),
    principal: principalA, ownership: ownership)
  #expect(destroyed.error == nil)
}
