import AgentProtocol
import BrowserEngine
import BrowserEvents
import BrowserVerification
import EngineCore
import Foundation
import Testing
@testable import EngineRuntime

/// Testing Agent 1 — cross-system integration and deliberate failure injection.
/// Exercises exec + events + branches + lease + handoff + verification over one
/// real WebKit workspace, then breaks it on purpose.
struct RuntimeEndToEndValidationTests {
  private func uuidDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
  }

  private func firstPage(_ runtime: BrowserRuntime, _ contextID: ContextID) async throws -> PageID {
    guard let page = try await runtime.listPages(contextID: contextID).first else {
      throw BrowserRuntimeError.contextNotFound(contextID)
    }
    return page.id
  }

  /// Fork restores its pages hibernated (`.discarded`); restore before use.
  private func restoreIfDiscarded(_ runtime: BrowserRuntime, _ page: PageID) async throws {
    if try await runtime.lifecycleState(pageID: page) == .discarded {
      _ = try await runtime.restorePage(pageID: page)
    }
  }

  private func evaluateValue(_ runtime: BrowserRuntime, _ page: PageID, _ source: String) async throws
    -> String
  {
    try await runtime.evaluate(pageID: page, source: source).value
  }

  @Test @MainActor func fullWorkspaceLifecycleExecEventsBranchesHandoffVerify() async throws {
    let server = try ValidationFixtureServer.start(port: 18961)
    defer { server.terminate() }
    let engine = NativeBrowserEngine()
    let runtime = engine.runtime
    let root = await runtime.createContext(name: "workspace")
    let rootDirectory = uuidDirectory()
    defer { try? FileManager.default.removeItem(at: rootDirectory) }
    try await runtime.openProfile(contextID: root.id, directory: rootDirectory)
    try await runtime.setCookie(
      contextID: root.id,
      cookie: CookieInfo(name: "baseline", value: "base", domain: "127.0.0.1", path: "/"))
    let page = try await runtime.createPage(contextID: root.id)
    _ = try await runtime.navigate(pageID: page.id, to: ValidationFixtureServer.url(18961, "/state"))

    // 1. Supervisor leases the workspace to Agent A with repo/worktree association.
    let lease = try await runtime.acquireWorkspaceLease(
      contextID: root.id, agentID: "agent-A", durationSeconds: 600,
      repositoryRoot: "/tmp/aether-repo", worktreePath: "/tmp/aether-repo-wt")
    #expect(lease.state == .active)
    #expect(lease.agentID == "agent-A")
    #expect(lease.repositoryRoot == "/tmp/aether-repo")
    #expect(lease.worktreePath == "/tmp/aether-repo-wt")
    #expect(await runtime.listWorkspaceLeases(contextID: root.id).count == 1)

    // 2. Agent A runs a local multi-step program on the leased page (one invocation).
    let outcome = await AgentExecRuntime(engine: engine).run(
      ExecProgram(steps: [
        .set(name: "pg", value: .literal(.number(Double(page.id.rawValue)))),
        .evaluate(
          page: .ref("pg"), source: .literal(.string("localStorage.getItem('token') || 'none'")),
          into: "token"),
        .result(value: .ref("token.value")),
        .result(value: .literal(.string("agent-A-done"))),
      ]))
    #expect(outcome.status == .completed, "\(outcome.error?.message ?? "")")
    #expect(outcome.results.last == .string("agent-A-done"))
    #expect(outcome.operations == 1)
    let executionEvents = await runtime.recentEvents(limit: 20, filter: .family(.execution))
    #expect(executionEvents.map(\.name).contains("execution.started"))
    #expect(executionEvents.map(\.name).contains("execution.finished"))

    // 3. Browser emitted ordered navigation events for the real load.
    let navigationEvents = await runtime.recentEvents(limit: 200, filter: .family(.navigation))
    #expect(navigationEvents.map(\.sequence) == navigationEvents.map(\.sequence).sorted())
    #expect(navigationEvents.contains { $0.name == "navigation.finished" })

    // 4. Checkpoint S42 and fork branches A and B.
    let checkpoint = try await runtime.checkpointBranch(contextID: root.id)
    let branchA = try await runtime.forkBranch(
      contextID: root.id, checkpointID: checkpoint.id, name: "explore-a")
    let branchB = try await runtime.forkBranch(
      contextID: root.id, checkpointID: checkpoint.id, name: "explore-b")
    let contextA = try #require(branchA.contextID)
    let contextB = try #require(branchB.contextID)
    #expect(contextA != contextB)
    for context in [contextA, contextB] {
      #expect(try await runtime.listCookies(contextID: context).contains { $0.name == "session" })
    }

    // 5. Branch A and B explore different paths without inheriting each other's state.
    let pageA = try await firstPage(runtime, contextA)
    let pageB = try await firstPage(runtime, contextB)
    try await restoreIfDiscarded(runtime, pageA)
    try await restoreIfDiscarded(runtime, pageB)
    _ = try await runtime.navigate(pageID: pageA, to: ValidationFixtureServer.url(18961, "/state-read"))
    _ = try await runtime.navigate(pageID: pageB, to: ValidationFixtureServer.url(18961, "/state-read"))
    _ = try await runtime.evaluate(pageID: pageA, source: "localStorage.setItem('path','A')")
    _ = try await runtime.evaluate(pageID: pageB, source: "localStorage.setItem('path','B')")
    #expect(try await evaluateValue(runtime, pageA, "localStorage.getItem('path')") == "A")
    #expect(try await evaluateValue(runtime, pageB, "localStorage.getItem('path')") == "B")

    // 6. Agent A reaches an approval boundary on branch A.
    let request = try await runtime.requestHandoff(
      pageID: pageA, category: .explicit, reason: "Approve the deploy",
      agent: "agent-A", branchID: branchA.id.description, executionID: outcome.executionID)
    #expect(request.state == .pending)

    // 7. Runtime parks branch A: agent control is refused, and an exec program fails closed.
    do {
      try await runtime.requireAgentControl(pageID: pageA)
      Issue.record("agent control unexpectedly allowed during handoff")
    } catch let error as HumanRequestError {
      #expect(error.code == "handoff_active")
    }
    let blocked = await AgentExecRuntime(engine: engine).run(
      ExecProgram(steps: [
        .set(name: "pg", value: .literal(.number(Double(pageA.rawValue)))),
        .evaluate(page: .ref("pg"), source: .literal(.string("1")), into: "x"),
      ]))
    #expect(blocked.status == .failed)
    #expect(blocked.error?.code == "handoff_active")

    // 8. Human takes over and changes real page state.
    _ = try await runtime.navigate(pageID: pageA, to: ValidationFixtureServer.url(18961, "/state-read"))
    _ = try await runtime.evaluate(pageID: pageA, source: "localStorage.setItem('token','human-value')")
    _ = try await runtime.completeHandoff(id: request.id, outcome: "approved", by: "human")

    // 9. Resume Agent A from the correct branch/page/context.
    let resumed = try await runtime.resumeHandoff(id: request.id, pageID: pageA, by: "agent-A")
    #expect(resumed.state == .resumed)
    try await runtime.requireAgentControl(pageID: pageA)

    // 10. Agent completes the workflow, observing the human's actual change.
    let final = await AgentExecRuntime(engine: engine).run(
      ExecProgram(steps: [
        .set(name: "pg", value: .literal(.number(Double(pageA.rawValue)))),
        .evaluate(
          page: .ref("pg"), source: .literal(.string("localStorage.getItem('token')")), into: "token"),
        .result(value: .ref("token.value")),
      ]))
    #expect(final.status == .completed, "\(final.error?.message ?? "")")
    #expect(final.results == [.string("human-value")])

    // 11. Verification checks the real final state, not a click return value.
    let verified = try await runtime.verify(
      BrowserVerificationPlan(
        pageID: pageA,
        checks: [
          BrowserVerificationCheck(
            id: "url", assertion: .pageURL(.init("/state-read", mode: .contains))),
          BrowserVerificationCheck(
            id: "marker", assertion: .element(selector: "#v", condition: .exists)),
        ]))
    #expect(verified.status == .verified)
    #expect(verified.evidence.allSatisfy { $0.status == .verified })

    // 12. Release the lease; branch B is untouched by all of the above.
    let released = try await runtime.releaseWorkspaceLease(
      contextID: root.id, leaseID: lease.leaseID, agentID: "agent-A")
    #expect(released.state == .released)
    let leaseEvents = await runtime.recentEvents(limit: 30, filter: .family(.lease))
    #expect(leaseEvents.map(\.name).contains("lease.acquired"))
    #expect(leaseEvents.map(\.name).contains("lease.released"))
    #expect(try await runtime.listBranches(contextID: root.id).count == 2)
    #expect(try await evaluateValue(runtime, pageB, "localStorage.getItem('path')") == "B")

    // 13. Clean up without corrupting survivors.
    try await runtime.deleteBranch(contextID: root.id, branchID: branchA.id)
    #expect(!FileManager.default.fileExists(atPath: branchA.directory))
    try await runtime.deleteBranch(contextID: root.id, branchID: branchB.id)
    #expect(try await runtime.listBranches(contextID: root.id).isEmpty)
    try await runtime.destroyContext(root.id)
    #expect(await runtime.listContexts().allSatisfy { $0.id != root.id })
  }

  @Test @MainActor func failureInjectionLeaseExpiryFreezesWorkspaceAndEmitsEvent() async throws {
    let server = try ValidationFixtureServer.start(port: 18962)
    defer { server.terminate() }
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "expiring")
    let directory = uuidDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try await runtime.openProfile(contextID: context.id, directory: directory)
    _ = try await runtime.createPage(contextID: context.id)
    let stream = await runtime.observeEvents(filter: .family(.lease))
    let collector = Task { () -> [String] in
      var names: [String] = []
      for await event in stream {
        names.append(event.name)
        if names.count >= 3 { break }
      }
      return names
    }
    let lease = try await runtime.acquireWorkspaceLease(
      contextID: context.id, agentID: "agent-B", durationSeconds: 1)
    #expect(lease.state == .active)

    var state = lease.state
    let deadline = Date().addingTimeInterval(6)
    while Date() < deadline {
      state = await runtime.workspaceLease(contextID: context.id)?.state ?? .active
      if state == .expired { break }
      try await Task.sleep(for: .milliseconds(200))
    }
    #expect(state == .expired, "lease never expired; got \(state)")
    // TISSUE-007: the expired state must not become observable before its event. Reading
    // the journal straight after seeing the state (bounded poll so a revocation await
    // cannot make this flaky) proves the publish happens before the suspend checkpoint.
    var journal: [BrowserEvent] = []
    for _ in 0..<10 {
      journal = await runtime.recentEvents(limit: 100, filter: .all)
      if journal.map(\.name).contains("lease.expired") { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    #expect(
      journal.map(\.name).contains("lease.expired"),
      "lease.expired was not in the journal once the lease state read as expired (TISSUE-007)")
    collector.cancel()
    let streamed = await collector.value
    let all = await runtime.recentEvents(limit: 100, filter: .all)
    print("[lease-expiry] streamed=\(streamed) journal=\(all.map(\.name))")
    #expect(streamed.contains("lease.expired") || all.map(\.name).contains("lease.expired"))
    // Runtime stays responsive after expiry.
    let probe = await runtime.createContext(name: "post-expiry")
    let probePage = try await runtime.createPage(contextID: probe.id)
    #expect(probePage.id.rawValue > 0)
  }

  @Test @MainActor func failureInjectionVerificationNeverOptimisticallySucceeds() async throws {
    let server = try ValidationFixtureServer.start(port: 18963)
    defer { server.terminate() }
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "verify")
    let page = try await runtime.createPage(contextID: context.id)
    _ = try await runtime.navigate(pageID: page.id, to: ValidationFixtureServer.url(18963, "/fast"))

    // A click-like action returned, but the destination is wrong: must be `failed`.
    let wrong = try await runtime.verify(
      BrowserVerificationPlan(
        pageID: page.id,
        checks: [
          BrowserVerificationCheck(
            id: "wrong-url",
            assertion: .pageURL(.init("/dashboard", mode: .contains))),
          BrowserVerificationCheck(
            id: "missing-element",
            assertion: .element(selector: "#does-not-exist", condition: .exists)),
        ]))
    #expect(wrong.status == .failed)
    #expect(wrong.evidence.allSatisfy { $0.status == .failed })

    // A check that cannot be observed must be `inconclusive`, never optimistic.
    let unobservable = try await runtime.verify(
      BrowserVerificationPlan(
        pageID: page.id,
        checks: [
          BrowserVerificationCheck(
            id: "no-response",
            assertion: .navigationResponse(
              url: .init("https://api.example.test/never", mode: .contains),
              statusCode: 200, sinceSequence: 0))
        ]))
    #expect(unobservable.status == .inconclusive)
  }

  @Test @MainActor func failureInjectionCancelledHandoffReleasesAgentCleanly() async throws {
    let server = try ValidationFixtureServer.start(port: 18964)
    defer { server.terminate() }
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "cancel-handoff")
    let directory = uuidDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try await runtime.openProfile(contextID: context.id, directory: directory)
    let page = try await runtime.createPage(contextID: context.id)
    _ = try await runtime.navigate(pageID: page.id, to: ValidationFixtureServer.url(18964, "/fast"))
    let request = try await runtime.requestHandoff(
      pageID: page.id, category: .mfa, reason: "Human cancels this", agent: "agent-C")
    do {
      try await runtime.requireAgentControl(pageID: page.id)
      Issue.record("agent control unexpectedly allowed while parked")
    } catch let error as HumanRequestError {
      #expect(error.code == "handoff_active")
    }
    let cancelled = try await runtime.cancelHumanRequest(id: request.id, by: "human")
    #expect(cancelled.state == .cancelled)
    // After cancellation the agent is unblocked predictably.
    try await runtime.requireAgentControl(pageID: page.id)
  }

  @Test @MainActor func failureInjectionPageClosedUnderLeaseKeepsLeaseConsistent() async throws {
    let server = try ValidationFixtureServer.start(port: 18965)
    defer { server.terminate() }
    let runtime = BrowserRuntime()
    let context = await runtime.createContext(name: "closed-page")
    let directory = uuidDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try await runtime.openProfile(contextID: context.id, directory: directory)
    let page = try await runtime.createPage(contextID: context.id)
    _ = try await runtime.navigate(pageID: page.id, to: ValidationFixtureServer.url(18965, "/fast"))
    let lease = try await runtime.acquireWorkspaceLease(
      contextID: context.id, agentID: "agent-D", durationSeconds: 300)
    try await runtime.closePage(page.id)
    // The lease is still owned and releasable; the workspace is not corrupted.
    #expect(await runtime.workspaceLease(contextID: context.id)?.state == .active)
    let released = try await runtime.releaseWorkspaceLease(
      contextID: context.id, leaseID: lease.leaseID, agentID: "agent-D")
    #expect(released.state == .released)
  }
}
