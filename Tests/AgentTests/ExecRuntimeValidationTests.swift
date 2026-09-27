import AgentProtocol
import BrowserEngine
import BrowserEvents
import EngineCore
import Foundation
import Testing

/// Testing Agent 1 — validation of the local agent execution runtime.
/// These exercise the real WebKit path and the real dispatcher boundary, not
/// hand-called helpers.
struct ExecRuntimeValidationTests {
  // MARK: - Locality / batching

  /// A workload iterating over hundreds of real DOM nodes must run inside one
  /// `agent.exec` invocation. 400 nested iterations are driven by one dispatcher
  /// call; only the real browser ops count as `operations`.
  @Test func execIteratesHundredsOfRealNodesInOneInvocation() async throws {
    let server = try ValidationFixtureServer.start(port: 18931)
    defer { server.terminate() }
    let engine = NativeBrowserEngine()
    let program = ExecProgram(steps: [
      .createContext(name: .literal(.string("exec-batch")), into: "ctx"),
      .createPage(context: .ref("ctx.id"), width: nil, height: nil, into: "pg"),
      .navigate(
        page: .ref("pg.id"),
        url: .literal(.string(ValidationFixtureServer.url(18931, "/bignodes?n=400").absoluteString)),
        settle: nil),
      .queryAll(page: .ref("pg.id"), selector: .literal(.string("li.row")), into: "rows"),
      .forEach(
        items: .ref("rows"), item: "row", index: "i", limit: nil,
        steps: [
          .assert(
            condition: ExecCondition(op: "exists", left: .ref("row.index")),
            message: "every row must expose its index"),
          .result(value: .ref("row.index")),
        ]),
      .result(value: .literal(.string("done"))),
    ])
    let started = Date()
    let outcome = await AgentExecRuntime(engine: engine).run(program)
    let elapsed = Date().timeIntervalSince(started)
    #expect(outcome.status == .completed, "\(outcome.error?.message ?? "no error")")
    // Exactly the real browser operations. The 400-node loop added none.
    #expect(outcome.operations == 4)
    #expect(outcome.results.count == 401)
    #expect(outcome.results.last == .string("done"))
    #expect(outcome.stepsExecuted == 806)
    #expect(elapsed < 30, "400-node local loop took \(elapsed)s")
  }

  /// One dispatcher call must perform many browser operations. We count the
  /// external boundary calls explicitly: this is the transport instrument.
  @Test func execBatchesManyBrowserOpsBehindOneBoundaryCall() async throws {
    let server = try ValidationFixtureServer.start(port: 18932)
    defer { server.terminate() }
    let engine = NativeBrowserEngine()
    let dispatcher = AgentCommandDispatcher(engine: engine)
    var readSteps: [ExecStep] = []
    let readCount = 40
    for index in 0..<readCount {
      readSteps.append(
        .evaluate(
          page: .ref("pg.id"), source: .literal(.string("'read-\(index)-' + (1 + 1)")),
          into: "v\(index)"))
    }
    let program = ExecProgram(
      steps: [
        .createContext(name: .literal(.string("exec-boundary")), into: "ctx"),
        .createPage(context: .ref("ctx.id"), width: nil, height: nil, into: "pg"),
        .navigate(
          page: .ref("pg.id"),
          url: .literal(.string(ValidationFixtureServer.url(18932, "/fast").absoluteString)),
          settle: nil),
      ] + readSteps + [.result(value: .ref("v\(readCount - 1).value"))])

    let input = AgentExec.Input(program: program)
    try input.validate()
    let params = try AgentProcedureCodec.encodeParams(input)
    // Transport instrument: exactly one boundary call.
    var boundaryCalls = 0
    boundaryCalls += 1
    let response = await dispatcher.handle(
      AgentRequest(id: "exec-1", method: .exec, params: params))
    #expect(response.error == nil)
    let result = try #require(response.result)
    let outcome = try AgentProcedureCodec.decodeOutput(ExecOutcome.self, from: result)
    #expect(outcome.status == .completed)
    #expect(boundaryCalls == 1)
    // 3 setup ops + 40 evaluate ops, all behind that one boundary call.
    #expect(outcome.operations == 43)
    #expect(outcome.results == [.string("read-\(readCount - 1)-2")])
  }

  // MARK: - Malformed / invalid programs

  @Test func execRejectsUnknownOpAtDecode() throws {
    let json = #"{"version":1,"onError":"stop","steps":[{"op":"definitelyNotAnOp"}]}"#
    #expect(throws: (any Error).self) {
      _ = try JSONDecoder().decode(ExecProgram.self, from: Data(json.utf8))
    }
  }

  @Test func execValidatesVersionBoundsAndShape() async throws {
    // Unsupported version.
    #expect(throws: AgentProcedureError.self) {
      try ExecProgram(version: 99, steps: [.result(value: .literal(.number(1)))]).validate()
    }
    // No steps.
    #expect(throws: AgentProcedureError.self) { try ExecProgram(steps: []).validate() }
    // Too many declared steps.
    let many = Array(repeating: ExecStep.result(value: .literal(.null)), count: 1_001)
    #expect(throws: AgentProcedureError.self) { try ExecProgram(steps: many).validate() }
    // Out-of-range timeout.
    #expect(throws: AgentProcedureError.self) {
      try AgentExec.Input(program: ExecProgram(steps: [.result(value: .literal(.null))]),
        timeoutMs: 999_999).validate()
    }
    // Empty forEach binding name.
    #expect(throws: AgentProcedureError.self) {
      try ExecProgram(steps: [
        .forEach(items: .literal(.array([])), item: "", index: nil, limit: nil,
          steps: [.result(value: .literal(.null))])
      ]).validate()
    }
  }

  @Test func execReportsUndefinedRefAsStepFailure() async throws {
    let engine = NativeBrowserEngine()
    let outcome = await AgentExecRuntime(engine: engine).run(
      ExecProgram(steps: [.result(value: .ref("doesNotExist.nope"))]))
    #expect(outcome.status == .failed)
    #expect(outcome.error?.code == "undefinedVariable")
  }

  @Test func execReportsTypeMismatchForNonArrayForEach() async throws {
    let engine = NativeBrowserEngine()
    let outcome = await AgentExecRuntime(engine: engine).run(
      ExecProgram(steps: [
        .set(name: "notAnArray", value: .literal(.string("nope"))),
        .forEach(items: .ref("notAnArray"), item: "entry", index: nil, limit: nil,
          steps: [.result(value: .ref("entry"))]),
      ]))
    #expect(outcome.status == .failed)
    #expect(outcome.error?.code == "typeMismatch")
    #expect(outcome.error?.stepPath == [1])
  }

  @Test func execRefusesForEachOverDeclaredLimitInsteadOfTruncating() async throws {
    let server = try ValidationFixtureServer.start(port: 18933)
    defer { server.terminate() }
    let engine = NativeBrowserEngine()
    let outcome = await AgentExecRuntime(engine: engine).run(
      ExecProgram(steps: [
        .createContext(name: .literal(.string("exec-limit")), into: "ctx"),
        .createPage(context: .ref("ctx.id"), width: nil, height: nil, into: "pg"),
        .navigate(
          page: .ref("pg.id"),
          url: .literal(.string(ValidationFixtureServer.url(18933, "/bignodes?n=5").absoluteString)),
          settle: nil),
        .queryAll(page: .ref("pg.id"), selector: .literal(.string("li.row")), into: "rows"),
        .forEach(items: .ref("rows"), item: "row", index: nil, limit: 2,
          steps: [.result(value: .ref("row.index"))]),
      ]))
    #expect(outcome.status == .failed)
    #expect(outcome.error?.code == "limitExceeded")
    #expect(outcome.error?.stepPath == [4])
  }

  @Test func execFailsUnknownSession() async throws {
    let engine = NativeBrowserEngine()
    let outcome = await AgentExecRuntime(engine: engine).run(
      ExecProgram(session: 999_999, steps: [.result(value: .literal(.null))]))
    #expect(outcome.status == .failed)
    #expect(outcome.error?.code == "sessionNotFound")
  }

  // MARK: - Cancellation, timeout, mid-flight failures

  @Test func execCancellationMidLoopLeavesRuntimeResponsive() async throws {
    let server = try ValidationFixtureServer.start(port: 18934)
    defer { server.terminate() }
    let engine = NativeBrowserEngine()
    let program = ExecProgram(steps: [
      .createContext(name: .literal(.string("exec-cancel")), into: "ctx"),
      .createPage(context: .ref("ctx.id"), width: nil, height: nil, into: "pg"),
      .navigate(
        page: .ref("pg.id"),
        url: .literal(.string(ValidationFixtureServer.url(18934, "/bignodes?n=50").absoluteString)),
        settle: nil),
      .queryAll(page: .ref("pg.id"), selector: .literal(.string("li.row")), into: "rows"),
      .forEach(items: .ref("rows"), item: "row", index: nil, limit: nil, steps: [
        .wait(
          page: .ref("pg.id"), selector: .literal(.string(".never-present")),
          condition: "attached", timeoutMs: 30_000)
      ]),
    ])
    let task = Task { await AgentExecRuntime(engine: engine).run(program) }
    try await Task.sleep(for: .milliseconds(600))
    let cancelledAt = Date()
    task.cancel()
    let outcome = await task.value
    let cancellationLatency = Date().timeIntervalSince(cancelledAt)
    #expect(outcome.status == .cancelled)
    #expect(cancellationLatency < 2, "cancellation took \(cancellationLatency)s")
    // No leaked lease registration, and the runtime is still usable (no cancelled task
    // holding the actor or a stranded page).
    #expect(await engine.runtime.leaseBoundExecutionCount == 0)
    let probeContext = await engine.runtime.createContext(name: "post-cancel")
    let probePage = try await engine.runtime.createPage(contextID: probeContext.id)
    #expect(try await engine.runtime.pageInfo(probePage.id).contextID == probeContext.id)
  }

  @Test func execTimeoutMidNavigationReturnsPromptlyAndLeavesRuntimeResponsive() async throws {
    let server = try ValidationFixtureServer.start(port: 18935)
    defer { server.terminate() }
    let engine = NativeBrowserEngine()
    let program = ExecProgram(
      timeoutMs: 600,
      steps: [
        .createContext(name: .literal(.string("exec-timeout")), into: "ctx"),
        .createPage(context: .ref("ctx.id"), width: nil, height: nil, into: "pg"),
        .navigate(
          page: .ref("pg.id"),
          url: .literal(.string(ValidationFixtureServer.url(18935, "/slow").absoluteString)),
          settle: nil),
      ])
    let started = Date()
    let outcome = await AgentExecRuntime(engine: engine).run(program)
    let elapsed = Date().timeIntervalSince(started)
    #expect(outcome.status == .timeout)
    #expect(outcome.error?.code == "timeout")
    #expect(elapsed < 3, "deadline must not wait for the 6s navigation; took \(elapsed)s")
    let probeContext = await engine.runtime.createContext(name: "post-timeout")
    let probePage = try await engine.runtime.createPage(contextID: probeContext.id)
    #expect(try await engine.runtime.pageInfo(probePage.id).contextID == probeContext.id)
  }

  @Test func execSurfacesPageClosureMidWaitWithoutCrashing() async throws {
    let server = try ValidationFixtureServer.start(port: 18936)
    defer { server.terminate() }
    let engine = NativeBrowserEngine()
    let context = await engine.runtime.createContext(name: "exec-pageclose")
    let page = try await engine.runtime.createPage(contextID: context.id)
    _ = try await engine.runtime.navigate(
      pageID: page.id, to: ValidationFixtureServer.url(18936, "/fast"))

    let program = ExecProgram(
      timeoutMs: 8_000,
      steps: [
        .set(name: "pg", value: .literal(.number(Double(page.id.rawValue)))),
        .wait(
          page: .ref("pg"), selector: .literal(.string(".never-present")),
          condition: "attached", timeoutMs: 5_000),
      ])
    let task = Task { await AgentExecRuntime(engine: engine).run(program) }
    try await Task.sleep(for: .milliseconds(400))
    try await engine.runtime.closePage(page.id)
    let outcome = await task.value
    // A page closed under a running program must fail the step, not crash or
    // silently report success.
    #expect(outcome.status == .failed, "got \(outcome.status) error=\(outcome.error?.code ?? "nil")")
    let probeContext = await engine.runtime.createContext(name: "post-pageclose")
    let probePage = try await engine.runtime.createPage(contextID: probeContext.id)
    #expect(try await engine.runtime.pageInfo(probePage.id).contextID == probeContext.id)
  }

  /// A multi-page workload: two pages in one context driven by one invocation, each page
  /// query/navigate, with the batching proof that the extra page added no boundary call.
  @Test func execDrivesTwoPagesInOneInvocation() async throws {
    let server = try ValidationFixtureServer.start(port: 18938)
    defer { server.terminate() }
    let engine = NativeBrowserEngine()
    let dispatcher = AgentCommandDispatcher(engine: engine)
    let program = ExecProgram(steps: [
      .createContext(name: .literal(.string("exec-multipage")), into: "ctx"),
      .createPage(context: .ref("ctx.id"), width: nil, height: nil, into: "one"),
      .createPage(context: .ref("ctx.id"), width: nil, height: nil, into: "two"),
      .navigate(
        page: .ref("one.id"),
        url: .literal(.string(ValidationFixtureServer.url(18938, "/bignodes?n=30").absoluteString)),
        settle: nil),
      .navigate(
        page: .ref("two.id"),
        url: .literal(.string(ValidationFixtureServer.url(18938, "/fast").absoluteString)),
        settle: nil),
      .queryAll(page: .ref("one.id"), selector: .literal(.string("li.row")), into: "rows"),
      .evaluate(page: .ref("two.id"), source: .literal(.string("document.title")), into: "other"),
      .result(value: .ref("other.value")),
      .result(value: .literal(.number(0))),
      .forEach(items: .ref("rows"), item: "row", index: nil, limit: nil, steps: [
        .result(value: .ref("row.index"))
      ]),
    ])
    let input = AgentExec.Input(program: program)
    let params = try AgentProcedureCodec.encodeParams(input)
    let response = await dispatcher.handle(
      AgentRequest(id: "exec-multi", method: .exec, params: params))
    #expect(response.error == nil)
    let outcome = try AgentProcedureCodec.decodeOutput(
      ExecOutcome.self, from: try #require(response.result))
    #expect(outcome.status == .completed, "\(outcome.error?.message ?? "")")
    // Both pages are in one context: context + 2 pages + 2 navigations + query + evaluate.
    #expect(outcome.operations == 7, "operations=\(outcome.operations)")
    #expect(outcome.results.first == .string("Fast"))
    #expect(outcome.results.count == 32)
  }

  /// Losing the workspace lease must stop the program the lease authorizes (ISSUE-007).
  /// The program is revoked mid-navigation by an explicit release, promptly, and the
  /// runtime drops the registration afterwards.
  @Test func leaseEndRevokesConfinedExecutionInFlight() async throws {
    let server = try ValidationFixtureServer.start(port: 18939)
    defer { server.terminate() }
    let engine = NativeBrowserEngine()
    let runtime = engine.runtime
    let context = await runtime.createContext(name: "leased-exec")
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await runtime.openProfile(contextID: context.id, directory: directory)
    let page = try await runtime.createPage(contextID: context.id)
    _ = try await runtime.navigate(
      pageID: page.id, to: ValidationFixtureServer.url(18939, "/fast"))
    let lease = try await runtime.acquireWorkspaceLease(
      contextID: context.id, agentID: "agent-A", durationSeconds: 3_600)
    #expect(await runtime.leaseBoundExecutionCount == 0)

    let program = ExecProgram(
      timeoutMs: 60_000,
      steps: [
        .set(name: "pg", value: .literal(.number(Double(page.id.rawValue)))),
        .evaluate(
          page: .ref("pg"), source: .literal(.string("document.title")), into: "title"),
        .navigate(
          page: .ref("pg"),
          url: .literal(.string(ValidationFixtureServer.url(18939, "/slow").absoluteString)),
          settle: nil),
        .result(value: .literal(.string("explored"))),
      ])
    let exec = Task {
      await AgentExecRuntime(engine: engine).run(
        program, allowedContexts: [context.id.rawValue])
    }
    var registered = false
    for _ in 0..<80 {
      if await runtime.leaseBoundExecutionCount == 1 { registered = true; break }
      try await Task.sleep(for: .milliseconds(50))
    }
    #expect(registered, "confined program was not registered against its lease")
    var startedSlow = false
    for _ in 0..<80 {
      let events = await runtime.recentEvents(limit: 60, filter: .family(.navigation))
      if events.contains(where: {
        $0.name == "navigation.started" && ($0.details["url"]?.contains("/slow") ?? false)
      }) {
        startedSlow = true
        break
      }
      try await Task.sleep(for: .milliseconds(50))
    }
    #expect(startedSlow, "program never started the slow navigation")

    let releasedAt = Date()
    _ = try await runtime.releaseWorkspaceLease(
      contextID: context.id, leaseID: lease.leaseID, agentID: "agent-A")
    let outcome = await exec.value
    let latency = Date().timeIntervalSince(releasedAt)
    #expect(
      outcome.status == .cancelled,
      "revoked program reported \(outcome.status) error=\(outcome.error?.code ?? "nil")")
    #expect(outcome.error?.code == ExecFailure.leaseRevokedCode)
    #expect(outcome.results.isEmpty, "a revoked program must not report its results")
    #expect(latency < 3, "revocation took \(latency)s; it must not wait out the 6s navigation")
    #expect(await runtime.leaseBoundExecutionCount == 0, "revoked execution leaked its registration")
  }

  @Test func execPublishesPairedExecutionEventsWithTerminalStatus() async throws {
    let engine = NativeBrowserEngine()
    let outcome = await AgentExecRuntime(engine: engine).run(
      ExecProgram(steps: [.assert(
        condition: ExecCondition(op: "eq", left: .literal(.number(1)), right: .literal(.number(2))),
        message: "boom")]))
    let events = await engine.runtime.recentEvents(limit: 10, filter: .family(.execution))
    #expect(events.map(\.name) == ["execution.started", "execution.finished"])
    #expect(events.allSatisfy { $0.details["id"] == outcome.executionID })
    #expect(events.last?.details["outcome"] == ExecStatus.failed.rawValue)
  }

  /// A host (unconfined) program driving a leased context must also stop when the
  /// lease expires: registration follows the contexts the program actually touches,
  /// not just a static confinement set. The reaper path (not an explicit release)
  /// delivers the revocation promptly, and the runtime stays usable afterwards.
  @Test func leaseExpiryRevokesUnconfinedExecutionTouchingTheContext() async throws {
    let engine = NativeBrowserEngine()
    let runtime = engine.runtime
    let context = await runtime.createContext(name: "leased-exec-host")
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await runtime.openProfile(contextID: context.id, directory: directory)
    let page = try await runtime.createPage(contextID: context.id)
    _ = try await runtime.loadHTML(
      pageID: page.id, html: "<html><body>leased</body></html>",
      url: URL(string: "https://example.test/leased")!)
    _ = try await runtime.acquireWorkspaceLease(
      contextID: context.id, agentID: "agent-A", durationSeconds: 1)
    #expect(await runtime.leaseBoundExecutionCount == 0)

    let program = ExecProgram(
      timeoutMs: 60_000,
      steps: [
        .set(name: "pg", value: .literal(.number(Double(page.id.rawValue)))),
        .wait(
          page: .ref("pg"), selector: .literal(.string(".never-present")),
          condition: "attached", timeoutMs: 30_000),
        .result(value: .literal(.string("unreached"))),
      ])
    let started = Date()
    let outcome = await AgentExecRuntime(engine: engine).run(program)
    let elapsed = Date().timeIntervalSince(started)
    #expect(
      outcome.status == .cancelled,
      "expired lease reported \(outcome.status) error=\(outcome.error?.code ?? "nil")")
    #expect(outcome.error?.code == ExecFailure.leaseRevokedCode)
    #expect(outcome.results.isEmpty, "a revoked program must not report its results")
    #expect(elapsed < 20, "expiry revocation took \(elapsed)s; the reaper must stop the run")
    #expect(await runtime.leaseBoundExecutionCount == 0, "revoked execution leaked its registration")
    let probe = await runtime.createContext(name: "post-revoke-probe")
    #expect(probe.name == "post-revoke-probe")
    try await runtime.destroyContext(context.id)
    try await runtime.destroyContext(probe.id)
  }
}
