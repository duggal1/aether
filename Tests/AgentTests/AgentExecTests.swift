import AgentProtocol
import BrowserEngine
import BrowserEvents
import EngineCore
import Foundation
import Testing

private func batchHTML(items: Int) -> String {
  let rows = (0..<items).map { "<li>Item \($0)</li>" }.joined()
  return "<html><body><ul>\(rows)</ul></body></html>"
}

private func scaffoldSteps(items: Int) -> [ExecStep] {
  [
    .createContext(name: .literal(.string("exec-test")), into: "ctx"),
    .createPage(context: .ref("ctx.id"), width: nil, height: nil, into: "pg"),
    .loadHTML(
      page: .ref("pg.id"), html: .literal(.string(batchHTML(items: items))),
      url: .literal(.string("https://example.test/batch"))),
  ]
}

@Test func execRunsMultiStepBatchWithLoopInOneInvocation() async throws {
  let engine = NativeBrowserEngine()
  let program = ExecProgram(
    steps: scaffoldSteps(items: 50) + [
      .queryAll(page: .ref("pg.id"), selector: .literal(.string("li")), into: "items"),
      .forEach(
        items: .ref("items"), item: "entry", index: "i", limit: nil,
        steps: [
          .assert(
            condition: ExecCondition(op: "exists", left: .ref("entry")),
            message: "each item must exist"),
          .result(value: .ref("entry.index")),
        ]),
      .result(value: .literal(.string("done"))),
    ])
  let outcome = await AgentExecRuntime(engine: engine).run(program)
  #expect(outcome.status == .completed)
  #expect(outcome.error == nil)
  #expect(outcome.failures.isEmpty)
  #expect(outcome.operations == 4)
  #expect(outcome.stepsExecuted == 106)
  #expect(outcome.results.count == 51)
  #expect(outcome.results.last == .string("done"))
  for value in outcome.results.dropLast() { #expect(value.number != nil) }
}

@Test func execSupportsVariablesConditionsAndBranches() async throws {
  let engine = NativeBrowserEngine()
  let program = ExecProgram(
    steps: [
      .set(name: "x", value: .literal(.number(3))),
      .conditional(
        condition: ExecCondition(op: "gt", left: .ref("x"), right: .literal(.number(2))),
        then: [.set(name: "y", value: .literal(.string("big")))],
        otherwise: [.set(name: "y", value: .literal(.string("small")))]),
      .assert(
        condition: ExecCondition(op: "eq", left: .ref("y"), right: .literal(.string("big"))),
        message: "branch"),
      .result(value: .ref("y")),
    ])
  let outcome = await AgentExecRuntime(engine: engine).run(program)
  #expect(outcome.status == .completed)
  #expect(outcome.results == [.string("big")])
  #expect(outcome.vars["y"] == .string("big"))
  #expect(outcome.operations == 0)
}

@Test func execPublishesLifecycleEvents() async throws {
  let engine = NativeBrowserEngine()
  let outcome = await AgentExecRuntime(engine: engine).run(
    ExecProgram(steps: [.result(value: .literal(.string("done")))]))
  let events = await engine.runtime.recentEvents(
    limit: 10, filter: .family(.execution))
  #expect(events.map(\.name) == ["execution.started", "execution.finished"])
  #expect(events.allSatisfy { $0.details["id"] == outcome.executionID })
  #expect(events.last?.details["outcome"] == ExecStatus.completed.rawValue)
}

@Test func execStopsOnAssertionFailureWithStepPath() async throws {
  let engine = NativeBrowserEngine()
  let program = ExecProgram(
    steps: [
      .set(name: "a", value: .literal(.number(1))),
      .assert(
        condition: ExecCondition(op: "eq", left: .ref("a"), right: .literal(.number(2))),
        message: "boom"),
      .result(value: .literal(.string("unreached"))),
    ])
  let outcome = await AgentExecRuntime(engine: engine).run(program)
  #expect(outcome.status == .failed)
  #expect(outcome.error?.code == "assertionFailed")
  #expect(outcome.error?.stepPath == [1])
  #expect(outcome.results.isEmpty)
}

@Test func execProceedModeCollectsFailuresAndContinues() async throws {
  let engine = NativeBrowserEngine()
  let program = ExecProgram(
    onError: .proceed,
    steps: [
      .set(name: "a", value: .literal(.number(1))),
      .assert(
        condition: ExecCondition(op: "eq", left: .ref("a"), right: .literal(.number(2))),
        message: "boom"),
      .result(value: .literal(.string("after"))),
    ])
  let outcome = await AgentExecRuntime(engine: engine).run(program)
  #expect(outcome.status == .completed)
  #expect(outcome.failures.count == 1)
  #expect(outcome.failures.first?.stepPath == [1])
  #expect(outcome.results == [.string("after")])
}

@Test func execEnforcesProgramDeadline() async throws {
  let engine = NativeBrowserEngine()
  let program = ExecProgram(
    timeoutMs: 400,
    steps: scaffoldSteps(items: 3) + [
      .wait(
        page: .ref("pg.id"), selector: .literal(.string(".never-present-xyz")),
        condition: "attached", timeoutMs: 30_000)
    ])
  let outcome = await AgentExecRuntime(engine: engine).run(program)
  #expect(outcome.status == .timeout)
  #expect(outcome.error?.code == "timeout")
}

@Test func execHonorsTaskCancellation() async throws {
  let engine = NativeBrowserEngine()
  let program = ExecProgram(
    steps: scaffoldSteps(items: 3) + [
      .wait(
        page: .ref("pg.id"), selector: .literal(.string(".never-present-xyz")),
        condition: "attached", timeoutMs: 30_000)
    ])
  let task = Task { await AgentExecRuntime(engine: engine).run(program) }
  try await Task.sleep(for: .milliseconds(300))
  task.cancel()
  let outcome = await task.value
  #expect(outcome.status == .cancelled)
}

@Test func execExposedThroughDispatcherAsSingleRPC() async throws {
  let dispatcher = AgentCommandDispatcher(engine: NativeBrowserEngine())
  let program = ExecProgram(
    steps: scaffoldSteps(items: 3) + [
      .queryAll(page: .ref("pg.id"), selector: .literal(.string("li")), into: "items"),
      .conditional(
        condition: ExecCondition(op: "exists", left: .ref("items[2]")),
        then: [.result(value: .literal(.string("three")))],
        otherwise: [.result(value: .literal(.string("other")))]),
    ])
  let input = AgentExec.Input(program: program)
  try input.validate()
  let params = try AgentProcedureCodec.encodeParams(input)
  let response = await dispatcher.handle(AgentRequest(id: "exec", method: .exec, params: params))
  #expect(response.error == nil)
  let result = try #require(response.result)
  let outcome = try AgentProcedureCodec.decodeOutput(ExecOutcome.self, from: result)
  #expect(outcome.status == .completed)
  #expect(outcome.results == [.string("three")])
  #expect(outcome.operations == 4)
  #expect(!outcome.executionID.isEmpty)
}
