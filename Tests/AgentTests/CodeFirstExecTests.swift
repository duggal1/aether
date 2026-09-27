import AgentProtocol
import BrowserEngine
import EngineCore
import Foundation
import Testing

/// Regression coverage for the code-first execution channel: persistent session state,
/// verification callable from inside a program, the generic Tier 2 bridge, and the
/// declared program-size cap. See `Docs/AGENT_CODE_FIRST_BROWSER_DIRECTIVE.md` §4.2, §5.1,
/// §5.3, §8.1.

private func scaffold() -> [ExecStep] {
  [
    .createContext(name: .literal(.string("code-first")), into: "ctx"),
    .createPage(context: .ref("ctx.id"), width: nil, height: nil, into: "pg"),
    .loadHTML(
      page: .ref("pg.id"),
      html: .literal(.string("<html><body><ul><li>one</li><li>two</li></ul></body></html>")),
      url: .literal(.string("https://example.test/code-first"))),
  ]
}

@Test func execSessionPersistsVariablesAcrossPrograms() async throws {
  let engine = NativeBrowserEngine()
  let session = await engine.runtime.createSession(name: "code-first-session").id.rawValue

  let seed = ExecProgram(
    session: session,
    steps: [
      .set(name: "count", value: .literal(.number(1))),
      .result(value: .ref("count")),
    ])
  let first = await AgentExecRuntime(engine: engine).run(seed)
  #expect(first.status == .completed)
  #expect(first.session == session)
  #expect(first.vars["count"] == .number(1))

  // The second program never sets `count`; the assertion only passes if the variable was
  // retained from the first program.
  let continueProgram = ExecProgram(
    session: session,
    steps: [
      .assert(
        condition: ExecCondition(
          op: "eq", left: .ref("count"), right: .literal(.number(1))),
        message: "session must retain variables"),
      .set(name: "count", value: .literal(.number(2))),
      .result(value: .ref("count")),
    ])
  let second = await AgentExecRuntime(engine: engine).run(continueProgram)
  #expect(second.status == .completed)
  #expect(second.results == [.number(2)])

  // A program with no session must not see the retained variable.
  let isolated = await AgentExecRuntime(engine: engine).run(
    ExecProgram(steps: [
      .assert(
        condition: ExecCondition(op: "notExists", left: .ref("count")),
        message: "session state must not leak into unbound programs"),
      .result(value: .literal(.string("isolated"))),
    ]))
  #expect(isolated.status == .completed)
}

@Test func execSessionSurvivesAnUnnamedProgramAndIsDestroyable() async throws {
  let engine = NativeBrowserEngine()
  let session = await engine.runtime.createSession(name: "destroyable").id.rawValue
  let seed = ExecProgram(
    session: session,
    steps: [
      .set(name: "token", value: .literal(.string("kept"))),
      .result(value: .ref("token")),
    ])
  let first = await AgentExecRuntime(engine: engine).run(seed)
  #expect(first.status == .completed)

  await engine.execSessions.destroy(session)
  let afterDestroy = await AgentExecRuntime(engine: engine).run(
    ExecProgram(
      session: session,
      steps: [
        .assert(
          condition: ExecCondition(op: "notExists", left: .ref("token")),
          message: "destroyed session must retain nothing"),
        .result(value: .literal(.string("clean"))),
      ]))
  #expect(afterDestroy.status == .completed)
}

@Test func execSessionRefusesConcurrentPrograms() async throws {
  let store = ExecSessionStore()
  _ = try await store.loadOrCreate(7)
  await #expect(throws: ExecSessionError.self) {
    try await store.loadOrCreate(7)
  }
  await store.endProgram(7)
  // The slot is released on a terminal path, so the next program is admitted.
  _ = try await store.loadOrCreate(7)
}

@Test func execProgramEnforcesDeclaredByteCap() throws {
  let filler = String(repeating: "a", count: 70 * 1024)
  let program = ExecProgram(steps: [
    .set(name: "big", value: .literal(.string(filler)))
  ])
  #expect(throws: AgentProcedureError.self) {
    try program.validate()
  }
}

@Test func execVerifyStepRunsFromInsideAProgram() async throws {
  let engine = NativeBrowserEngine()
  let program = ExecProgram(steps: scaffold() + [
    .verify(
      plan: .literal(
        .object([
          "page": .object(["ref": .string("pg.id")]),
          "checks": .array([
            .object([
              "id": .string("root"),
              "assertion": .object([
                "kind": .string("element"),
                "selector": .string("body"),
                "condition": .object(["kind": .string("exists")]),
              ]),
            ])
          ]),
        ])),
      into: "verification"),
  ])
  let outcome = await AgentExecRuntime(engine: engine).run(program)
  #expect(outcome.status == .completed, "verify must be callable from inside a program")
  #expect(outcome.counters.verificationChecks == 1)
  let result = try #require(outcome.vars["verification"]?.object)
  #expect(result["status"] != nil)
}

@Test func execCallStepInvokesRuntimeWithoutLeavingTheProgram() async throws {
  let engine = NativeBrowserEngine()
  let program = ExecProgram(steps: scaffold() + [
    .call(
      method: .literal(.string("page.query")),
      params: .literal(
        .object([
          "page": .object(["ref": .string("pg.id")]),
          "selector": .string("li"),
        ])),
      into: "firstItem"),
  ])
  let outcome = await AgentExecRuntime(engine: engine).run(program)
  #expect(outcome.status == .completed)
  #expect(outcome.counters.runtimeCalls == 1)
  #expect(outcome.vars["firstItem"] != .null)
  // One program is one boundary call regardless of how many operations it absorbed.
  #expect(outcome.counters.boundaryCalls == 1)
  #expect(outcome.counters.operations >= 4)
}

@Test func execCallStepRefusesMethodsOutsideTheProgramSurface() async throws {
  let engine = NativeBrowserEngine()
  let program = ExecProgram(steps: [
    .call(
      method: .literal(.string("agent.exec")),
      params: nil, into: "nope")
  ])
  let outcome = await AgentExecRuntime(engine: engine).run(program)
  #expect(outcome.status == .failed)
  #expect(outcome.error?.code == "unauthorized")
  #expect(outcome.counters.runtimeCalls == 0)
}
