import BrowserEvents
import BrowserVerification
import EngineCore
import EngineRuntime
import Foundation
import Testing

@Test @MainActor func leasedWebKitHandoffResumesIntoVerifiedHumanState() async throws {
  let runtime = BrowserRuntime()
  let context = await runtime.createContext(name: "handoff-verification")
  let profile = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  defer { try? FileManager.default.removeItem(at: profile) }
  try await runtime.openProfile(contextID: context.id, directory: profile)
  let page = try await runtime.createPage(contextID: context.id)
  _ = try await runtime.loadHTML(
    pageID: page.id,
    html: """
      <html><head><title>Approval pending</title></head>
      <body><input id="code"><p id="status">Waiting</p></body></html>
      """,
    url: URL(string: "https://example.test/approval")!)

  let branchID = UUID().uuidString
  let lease = try await runtime.acquireWorkspaceLease(
    contextID: context.id, agentID: "worker-a", durationSeconds: 30,
    branchID: branchID, repositoryRoot: "/tmp/aether-repo",
    worktreePath: "/tmp/aether-repo/.worktrees/worker-a")
  #expect(lease.state == .active)
  #expect(lease.branchID == branchID)

  let handoff = try await runtime.requestHandoff(
    pageID: page.id, category: .mfa, reason: "Complete the local approval",
    agent: "worker-a", branchID: branchID, executionID: "exec-handoff-1")
  do {
    try await runtime.requireAgentControl(pageID: page.id)
    Issue.record("Agent control must be blocked while the human owns the handoff")
  } catch let error as HumanRequestError {
    #expect(error.code == "handoff_active")
  }

  let privateValue = "human-private-code-4821"
  _ = try await runtime.evaluate(
    pageID: page.id,
    source: "document.querySelector('#code').value = '\(privateValue)'; document.querySelector('#status').textContent = 'Approved'; document.title = 'Approved'; true")
  let completed = try await runtime.completeHandoff(
    id: handoff.id, outcome: "approved", by: "human")
  #expect(completed.state == .completed)
  do {
    try await runtime.requireAgentControl(pageID: page.id)
    Issue.record("Agent control must stay parked until resume")
  } catch let error as HumanRequestError {
    #expect(error.code == "handoff_active")
  }
  let resumed = try await runtime.resumeHandoff(id: handoff.id, by: "worker-a")
  #expect(resumed.state == .resumed)
  #expect(resumed.page == page.id)
  #expect(resumed.context == context.id)

  let plan = BrowserVerificationPlan(
    pageID: page.id,
    checks: [
      BrowserVerificationCheck(id: "title", assertion: .pageTitle(.init("Approved"))),
      BrowserVerificationCheck(
        id: "status", assertion: .element(selector: "#status", condition: .visible)),
    ])
  let verification = try await runtime.verify(plan)
  #expect(verification.status == .verified)
  #expect(verification.contextID == context.id)
  #expect(verification.pageID == page.id)

  let handoffEvents = await runtime.recentEvents(
    limit: 50, filter: BrowserEventBus.Filter(families: [.handoff, .lease]))
  let relevant = handoffEvents.filter {
    $0.identity.context == context.id && $0.identity.page == page.id
      || $0.identity.context == context.id && $0.identity.branch == branchID
  }
  #expect(relevant.contains { $0.name == "handoff.requested" })
  #expect(relevant.contains { $0.name == "handoff.parked" })
  #expect(relevant.contains { $0.name == "handoff.completed" })
  #expect(relevant.contains { $0.name == "handoff.resumed" })
  #expect(relevant.contains { $0.name == "lease.acquired" })
  #expect(!String(describing: relevant).contains(privateValue))
  #expect(!String(describing: handoff).contains(privateValue))

  let released = try await runtime.releaseWorkspaceLease(
    contextID: context.id, leaseID: lease.leaseID, agentID: "worker-a")
  #expect(released.state == .released)
  #expect(try await runtime.lifecycleState(pageID: page.id) == .frozen)
  try await runtime.destroyContext(context.id)
}
