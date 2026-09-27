import AgentProtocol
import DOM
import EngineCore
import EngineRuntime
import Foundation

private final class ExecChildBox: @unchecked Sendable {
  private let lock = NSLock()
  private var task: Task<ExecOutcome, Never>?
  private var isCancelled = false

  func adopt(_ task: Task<ExecOutcome, Never>) {
    lock.lock()
    let cancelImmediately = isCancelled
    if !cancelImmediately { self.task = task }
    lock.unlock()
    if cancelImmediately { task.cancel() }
  }

  func cancel() {
    lock.lock()
    isCancelled = true
    let task = self.task
    self.task = nil
    lock.unlock()
    task?.cancel()
  }
}

public struct AgentExecRuntime: Sendable {
  public let engine: NativeBrowserEngine

  public init(engine: NativeBrowserEngine) {
    self.engine = engine
  }

  public func run(
    _ program: ExecProgram, timeoutMs: UInt64? = nil, allowedContexts: Set<UInt64>? = nil
  ) async -> ExecOutcome {
    let runner = self
    let state = ExecRunState()
    let box = ExecChildBox()
    let contexts = Set((allowedContexts ?? []).map { ContextID(rawValue: $0) })
    let token = await engine.runtime.registerLeaseBoundExecution(contexts: contexts) {
      box.cancel()
      await state.requestRevocation()
    }
    let child = Task<ExecOutcome, Never> {
      await runner.runInner(
        program: program, timeoutMs: timeoutMs, allowedContexts: allowedContexts,
        state: state, revocation: token)
    }
    box.adopt(child)
    return await withTaskCancellationHandler {
      let outcome = await child.value
      await engine.runtime.unregisterLeaseBoundExecution(token)
      return outcome
    } onCancel: {
      child.cancel()
    }
  }

  private func runInner(
    program: ExecProgram, timeoutMs: UInt64?, allowedContexts: Set<UInt64>?,
    state: ExecRunState, revocation: LeaseRevocationToken
  ) async -> ExecOutcome {
    let executionID = UUID().uuidString
    let requested = timeoutMs ?? program.timeoutMs ?? ExecLimits.defaultTimeoutMs
    let effective = min(max(requested, 1), ExecLimits.maxTimeoutMs)
    await engine.runtime.events.publish(.executionStarted(id: executionID))
    let outcome: ExecOutcome
    do {
      outcome = try await withThrowingTaskGroup(of: ExecOutcome.self) { group in
        group.addTask {
          await self.execute(
            program: program, executionID: executionID, state: state,
            allowedContexts: allowedContexts, revocation: revocation)
        }
        group.addTask {
          try await Task.sleep(for: .milliseconds(Int64(effective)))
          throw ExecDeadline.exceeded
        }
        do {
          if let first = try await group.next() {
            group.cancelAll()
            return first
          }
        } catch is ExecDeadline {
          group.cancelAll()
          var snapshot = await state.snapshot()
          snapshot.executionID = executionID
          snapshot.status = .timeout
          snapshot.error = ExecFailure(
            stepPath: [], op: "exec", code: "timeout",
            message: "Exec program exceeded its \(effective)ms deadline")
          return snapshot
        }
        group.cancelAll()
        var snapshot = await state.snapshot()
        snapshot.executionID = executionID
        snapshot.status = .cancelled
        return snapshot
      }
    } catch is CancellationError {
      var snapshot = await state.snapshot()
      snapshot.executionID = executionID
      if snapshot.status == .completed { snapshot.status = .cancelled }
      if snapshot.error == nil, let reason = await state.revocation() {
        snapshot.error = ExecFailure(
          stepPath: [], op: "exec", code: ExecFailure.leaseRevokedCode, message: reason)
      }
      outcome = snapshot
    } catch {
      var snapshot = await state.snapshot()
      snapshot.executionID = executionID
      snapshot.status = .failed
      snapshot.error = ExecFailure(
        stepPath: [], op: "exec", code: "engine_error",
        message: String(describing: error))
      outcome = snapshot
    }
    await engine.runtime.events.publish(
      .executionFinished(id: executionID, outcome: outcome.status.rawValue))
    return outcome
  }

  private func execute(
    program: ExecProgram, executionID: String, state: ExecRunState,
    allowedContexts: Set<UInt64>?, revocation: LeaseRevocationToken
  ) async -> ExecOutcome {
    do {
      try Task.checkCancellation()
      if let session = program.session {
        let sessions = await engine.runtime.listSessions()
        guard sessions.contains(where: { $0.id.rawValue == session }) else {
          throw ExecStepError(
            failure: ExecFailure(
              stepPath: [], op: "exec", code: "sessionNotFound",
              message: "Session not found: \(session)"))
        }
      }
      try await runSteps(
        program.steps, path: [], state: state, onError: program.onError,
        allowedContexts: allowedContexts, revocation: revocation)
      var snapshot = await state.snapshot()
      snapshot.executionID = executionID
      snapshot.status = .completed
      return snapshot
    } catch is CancellationError {
      var snapshot = await state.snapshot()
      snapshot.executionID = executionID
      snapshot.status = .cancelled
      if let reason = await state.revocation() {
        snapshot.error = ExecFailure(
          stepPath: [], op: "exec", code: ExecFailure.leaseRevokedCode, message: reason)
      }
      return snapshot
    } catch let error as ExecStepError {
      var snapshot = await state.snapshot()
      snapshot.executionID = executionID
      snapshot.status = error.failure.code == ExecFailure.leaseRevokedCode ? .cancelled : .failed
      snapshot.error = error.failure
      return snapshot
    } catch {
      var snapshot = await state.snapshot()
      snapshot.executionID = executionID
      snapshot.status = .failed
      snapshot.error = ExecFailure(
        stepPath: [], op: "exec", code: "engine_error",
        message: String(describing: error))
      return snapshot
    }
  }

  private func runSteps(
    _ steps: [ExecStep], path: [Int], state: ExecRunState, onError: ExecOnError,
    allowedContexts: Set<UInt64>?, revocation: LeaseRevocationToken
  ) async throws {
    for (offset, step) in steps.enumerated() {
      let stepPath = path + [offset]
      try Task.checkCancellation()
      if let reason = await state.revocation() {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: stepPath, op: step.op, code: ExecFailure.leaseRevokedCode,
            message: reason))
      }
      let executed = await state.noteStep()
      guard executed <= ExecLimits.maxExecutedSteps else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: stepPath, op: step.op, code: "limitExceeded",
            message: "Exec program exceeded \(ExecLimits.maxExecutedSteps) executed steps"))
      }
      do {
        try await runStep(step, path: stepPath, state: state, onError: onError,
          allowedContexts: allowedContexts, revocation: revocation)
      } catch is CancellationError {
        throw CancellationError()
      } catch let error as ExecStepError {
        // A revoked workspace stops the program no matter how the program was configured
        // to treat step failures: `onError: proceed` must not outlive the lease.
        if onError == .stop || error.failure.code == ExecFailure.leaseRevokedCode {
          throw error
        }
        await state.noteFailure(error.failure)
        if let into = step.intoTarget { await state.setVar(into, value: .null) }
      }
    }
  }

  private func runStep(
    _ step: ExecStep, path: [Int], state: ExecRunState, onError: ExecOnError,
    allowedContexts: Set<UInt64>?, revocation: LeaseRevocationToken
  ) async throws {
    let vars = await state.vars
    switch step {
    case .createContext(let name, _):
      if allowedContexts != nil {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: step.op, code: "unauthorized",
            message: "Non-host principals create contexts via context.create first"))
      }
      let context = await engine.runtime.createContext(
        name: try name.stringValue(vars, what: "name"))
      await state.noteOperation()
      await engine.runtime.expandLeaseBoundExecution(revocation, context: context.id)
      await bind(step, value: execContextJSON(context), state: state, path: path)
    case .createPage(let contextValue, let width, let height, _):
      let contextID = ContextID(rawValue: try contextValue.uint64Value(vars, what: "context"))
      try await gateContext(contextID, path: path, op: step.op, allowedContexts: allowedContexts, revocation: revocation)
      let viewport = try viewportSize(width: width, height: height, path: path, op: step.op)
      let page = try await browser(path: path, op: step.op) {
        try await self.engine.runtime.createPage(contextID: contextID, viewport: viewport)
      }
      await state.noteOperation()
      await bind(step, value: execPageJSON(page), state: state, path: path)
    case .navigate(let pageValue, let urlValue, let settle):
      let page = try await requirePage(
        pageValue, vars: vars, path: path, op: step.op, allowedContexts: allowedContexts, revocation: revocation)
      let raw = try urlValue.stringValue(vars, what: "url")
      guard let url = URL(string: raw) else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: step.op, code: "badParameter", message: "url"))
      }
      let readiness = settle.flatMap(PageReadiness.init(rawValue:)) ?? .complete
      let info = try await browser(path: path, op: step.op) {
        try await self.engine.runtime.navigate(pageID: page, to: url, settle: readiness)
      }
      await state.noteOperation()
      await bind(step, value: execPageJSON(info), state: state, path: path)
    case .loadHTML(let pageValue, let htmlValue, let urlValue):
      let page = try await requirePage(
        pageValue, vars: vars, path: path, op: step.op, allowedContexts: allowedContexts, revocation: revocation)
      let html = try htmlValue.stringValue(vars, what: "html")
      let raw = try urlValue.stringValue(vars, what: "url")
      guard let url = URL(string: raw) else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: step.op, code: "badParameter", message: "url"))
      }
      let info = try await browser(path: path, op: step.op) {
        try await self.engine.runtime.loadHTML(pageID: page, html: html, url: url)
      }
      await state.noteOperation()
      await bind(step, value: execPageJSON(info), state: state, path: path)
    case .query(let pageValue, let selectorValue, _):
      let page = try await requirePage(
        pageValue, vars: vars, path: path, op: step.op, allowedContexts: allowedContexts, revocation: revocation)
      let selector = try selectorValue.stringValue(vars, what: "selector")
      let node = try await browser(path: path, op: step.op) {
        try await self.engine.runtime.query(pageID: page, selector: selector)
      }
      await state.noteOperation()
      await bind(step, value: node.map(execNodeJSON) ?? .null, state: state, path: path)
    case .queryAll(let pageValue, let selectorValue, _):
      let page = try await requirePage(
        pageValue, vars: vars, path: path, op: step.op, allowedContexts: allowedContexts, revocation: revocation)
      let selector = try selectorValue.stringValue(vars, what: "selector")
      let nodes = try await browser(path: path, op: step.op) {
        try await self.engine.runtime.queryAll(pageID: page, selector: selector)
      }
      await state.noteOperation()
      await bind(step, value: .array(nodes.map(execNodeJSON)), state: state, path: path)
    case .click(let pageValue, let indexValue, let generationValue):
      let page = try await requirePage(
        pageValue, vars: vars, path: path, op: step.op, allowedContexts: allowedContexts, revocation: revocation)
      let node = try nodeID(
        index: indexValue, generation: generationValue, vars: vars, path: path, op: step.op)
      let info = try await browser(path: path, op: step.op) {
        try await self.engine.runtime.click(pageID: page, nodeID: node)
      }
      await state.noteOperation()
      await bind(step, value: execPageJSON(info), state: state, path: path)
    case .type(let pageValue, let indexValue, let generationValue, let textValue, let append):
      let page = try await requirePage(
        pageValue, vars: vars, path: path, op: step.op, allowedContexts: allowedContexts, revocation: revocation)
      let node = try nodeID(
        index: indexValue, generation: generationValue, vars: vars, path: path, op: step.op)
      let text = try textValue.stringValue(vars, what: "text")
      try await browser(path: path, op: step.op) {
        try await self.engine.runtime.type(
          pageID: page, nodeID: node, text: text, append: append ?? false)
      }
      await state.noteOperation()
      await bind(step, value: .object(["ok": .bool(true)]), state: state, path: path)
    case .evaluate(let pageValue, let sourceValue, _):
      let page = try await requirePage(
        pageValue, vars: vars, path: path, op: step.op, allowedContexts: allowedContexts, revocation: revocation)
      let source = try sourceValue.stringValue(vars, what: "source")
      let outcome = try await browser(path: path, op: step.op) {
        try await self.engine.runtime.evaluate(pageID: page, source: source)
      }
      await state.noteOperation()
      await bind(
        step,
        value: .object([
          "value": .string(outcome.value),
          "console": .array(outcome.console.map(JSONValue.string)),
        ]), state: state, path: path)
    case .snapshot(let pageValue, let limit, _):
      let page = try await requirePage(
        pageValue, vars: vars, path: path, op: step.op, allowedContexts: allowedContexts, revocation: revocation)
      if let limit, !(1...ExecLimits.maxSnapshotLimit).contains(limit) {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: step.op, code: "badParameter", message: "snapshot.limit"))
      }
      let snapshot = try await browser(path: path, op: step.op) {
        try await self.engine.runtime.snapshot(pageID: page, limit: limit ?? 20_000)
      }
      await state.noteOperation()
      await bind(step, value: try encodeJSON(snapshot), state: state, path: path)
    case .inspect(let pageValue, _):
      let page = try await requirePage(
        pageValue, vars: vars, path: path, op: step.op, allowedContexts: allowedContexts, revocation: revocation)
      let inspection = try await browser(path: path, op: step.op) {
        try await self.engine.runtime.inspect(pageID: page)
      }
      await state.noteOperation()
      await bind(step, value: try encodeJSON(inspection), state: state, path: path)
    case .wait(let pageValue, let selectorValue, let condition, let timeoutMs):
      let page = try await requirePage(
        pageValue, vars: vars, path: path, op: step.op, allowedContexts: allowedContexts, revocation: revocation)
      let selector = try selectorValue.stringValue(vars, what: "selector")
      let waitCondition =
        condition.flatMap(SelectorWaitCondition.init(rawValue:)) ?? .visible
      let node = try await browser(path: path, op: step.op) {
        try await self.engine.runtime.waitForSelector(
          pageID: page, selector: selector, condition: waitCondition,
          timeoutMilliseconds: timeoutMs ?? 5_000)
      }
      await state.noteOperation()
      await bind(step, value: node.map(execNodeJSON) ?? .null, state: state, path: path)
    case .restore(let pageValue, _):
      let page = try await requirePage(
        pageValue, vars: vars, path: path, op: step.op, allowedContexts: allowedContexts, revocation: revocation)
      let info = try await browser(path: path, op: step.op) {
        try await self.engine.runtime.restorePage(pageID: page)
      }
      await state.noteOperation()
      await bind(step, value: execPageJSON(info), state: state, path: path)
    case .set(let name, let value):
      await state.setVar(name, value: try value.resolve(vars))
    case .assert(let condition, let message):
      let passed = try evaluateCondition(condition, vars: vars, path: path, op: step.op)
      guard passed else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: step.op, code: "assertionFailed",
            message: message ?? "assertion failed"))
      }
    case .forEach(let itemsValue, let item, let index, let limit, let nested):
      let resolved = try itemsValue.resolve(vars)
      guard case .array(let elements) = resolved else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: step.op, code: "typeMismatch",
            message: "forEach.items must resolve to an array"))
      }
      if let limit, !(1...ExecLimits.maxItems).contains(limit) {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: step.op, code: "badParameter", message: "forEach.limit"))
      }
      let effective = limit ?? elements.count
      guard elements.count <= effective else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: step.op, code: "limitExceeded",
            message:
              "forEach found \(elements.count) items with limit \(effective); pass an explicit limit or narrow the query"
          ))
      }
      guard elements.count <= ExecLimits.maxItems else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: step.op, code: "limitExceeded",
            message: "forEach found \(elements.count) items; maximum is \(ExecLimits.maxItems)"))
      }
      let previousItem = await state.swapVar(item, value: .null)
      var previousIndex: JSONValue?
      if let index { previousIndex = await state.swapVar(index, value: .null) }
      do {
        for (position, element) in elements.prefix(effective).enumerated() {
          try Task.checkCancellation()
          await state.setVar(item, value: element)
          if let index { await state.setVar(index, value: .number(Double(position))) }
          try await runSteps(
            nested, path: path + [position], state: state, onError: onError,
            allowedContexts: allowedContexts, revocation: revocation)
        }
      } catch {
        await state.restoreVar(item, value: previousItem)
        if let index { await state.restoreVar(index, value: previousIndex) }
        throw error
      }
      await state.restoreVar(item, value: previousItem)
      if let index { await state.restoreVar(index, value: previousIndex) }
    case .conditional(let condition, let then, let otherwise):
      let passed = try evaluateCondition(condition, vars: vars, path: path, op: step.op)
      try await runSteps(
        passed ? then : otherwise ?? [], path: path, state: state, onError: onError,
        allowedContexts: allowedContexts, revocation: revocation)
    case .result(let value):
      await state.appendResult(try value.resolve(vars))
    }
  }

  private func bind(
    _ step: ExecStep, value: JSONValue, state: ExecRunState, path: [Int]
  ) async {
    if let into = step.intoTarget { await state.setVar(into, value: value) }
  }

  private func requirePage(
    _ value: ExecValue, vars: [String: JSONValue], path: [Int], op: String,
    allowedContexts: Set<UInt64>?, revocation: LeaseRevocationToken
  ) async throws -> PageID {
    let page = PageID(rawValue: try value.uint64Value(vars, what: "page", path: path, op: op))
    do {
      try await engine.runtime.requireAgentControl(pageID: page)
    } catch {
      throw mapError(error, path: path, op: op)
    }
    let info: BrowserPageInfo
    do {
      info = try await engine.runtime.pageInfo(page)
    } catch {
      throw mapError(error, path: path, op: op)
    }
    await engine.runtime.expandLeaseBoundExecution(revocation, context: info.contextID)
    try await gateContext(
      info.contextID, path: path, op: op, allowedContexts: allowedContexts,
      revocation: revocation)
    return page
  }

  private func gateContext(
    _ contextID: ContextID, path: [Int], op: String, allowedContexts: Set<UInt64>?,
    revocation: LeaseRevocationToken
  ) async throws {
    await engine.runtime.expandLeaseBoundExecution(revocation, context: contextID)
    if let allowedContexts, !allowedContexts.contains(contextID.rawValue) {
      throw ExecStepError(
        failure: ExecFailure(
          stepPath: path, op: op, code: "unauthorized",
          message: "Exec program touches context \(contextID.rawValue) outside its lease"))
    }
  }

  private func browser<T>(
    path: [Int], op: String, body: () async throws -> T
  ) async throws -> T {
    do {
      return try await body()
    } catch {
      throw mapErrorPreservingCancellation(error, path: path, op: op)
    }
  }

  private func mapErrorPreservingCancellation(_ error: Error, path: [Int], op: String) -> Error {
    if error is CancellationError { return error }
    return mapError(error, path: path, op: op)
  }

  private func mapError(_ error: Error, path: [Int], op: String) -> ExecStepError {
    if let error = error as? ExecStepError { return error }
    if let error = error as? HumanRequestError {
      return ExecStepError(
        failure: ExecFailure(
          stepPath: path, op: op, code: error.code, message: error.description))
    }
    if let error = error as? BrowserRuntimeError {
      if case .timeout = error {
        return ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: op, code: "timeout", message: error.description))
      }
      return ExecStepError(
        failure: ExecFailure(
          stepPath: path, op: op, code: "engine_error", message: error.description))
    }
    return ExecStepError(
      failure: ExecFailure(
        stepPath: path, op: op, code: "engine_error", message: String(describing: error)))
  }

  private func nodeID(
    index: ExecValue, generation: ExecValue, vars: [String: JSONValue], path: [Int], op: String
  ) throws -> NodeID {
    let rawIndex = try index.uint64Value(vars, what: "nodeIndex", path: path, op: op)
    let rawGeneration = try generation.uint64Value(
      vars, what: "nodeGeneration", path: path, op: op)
    guard let nodeIndex = UInt32(exactly: rawIndex),
      let nodeGeneration = UInt32(exactly: rawGeneration)
    else {
      throw ExecStepError(
        failure: ExecFailure(
          stepPath: path, op: op, code: "typeMismatch",
          message: "nodeIndex/nodeGeneration out of UInt32 range"))
    }
    return NodeID(index: nodeIndex, generation: nodeGeneration)
  }

  private func viewportSize(width: Double?, height: Double?, path: [Int], op: String) throws -> Size {
    let resolvedWidth = width ?? 1280
    let resolvedHeight = height ?? 800
    guard resolvedWidth.isFinite, resolvedHeight.isFinite, resolvedWidth > 0,
      resolvedHeight > 0
    else {
      throw ExecStepError(
        failure: ExecFailure(
          stepPath: path, op: op, code: "badParameter", message: "width/height"))
    }
    return Size(width: resolvedWidth, height: resolvedHeight)
  }

  private func evaluateCondition(
    _ condition: ExecCondition, vars: [String: JSONValue], path: [Int], op: String
  ) throws -> Bool {
    switch condition.op {
    case "exists":
      guard let value = try? condition.left.resolve(vars) else { return false }
      return value != .null
    case "notExists":
      guard let value = try? condition.left.resolve(vars) else { return true }
      return value == .null
    case "empty":
      guard let value = try? condition.left.resolve(vars) else { return true }
      switch value {
      case .null: return true
      case .string(let text): return text.isEmpty
      case .array(let items): return items.isEmpty
      case .object(let object): return object.isEmpty
      default: return false
      }
    case "eq", "ne":
      let left = try condition.left.resolve(vars)
      guard let right = condition.right else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: op, code: "badParameter",
            message: "condition \(condition.op) requires right"))
      }
      let equal = (try right.resolve(vars)) == left
      return condition.op == "eq" ? equal : !equal
    case "contains":
      let left = try condition.left.resolve(vars)
      guard let right = condition.right else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: op, code: "badParameter",
            message: "condition contains requires right"))
      }
      let needle = try right.resolve(vars)
      switch (left, needle) {
      case (.string(let haystack), .string(let fragment)): return haystack.contains(fragment)
      case (.array(let items), _): return items.contains(needle)
      default:
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: op, code: "typeMismatch",
            message: "condition contains needs string/array left side"))
      }
    case "gt", "lt":
      let left = try condition.left.resolve(vars)
      guard let right = condition.right else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: op, code: "badParameter",
            message: "condition \(condition.op) requires right"))
      }
      guard let leftNumber = left.number, let rightNumber = try right.resolve(vars).number
      else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: path, op: op, code: "typeMismatch",
            message: "condition \(condition.op) needs numeric sides"))
      }
      return condition.op == "gt" ? leftNumber > rightNumber : leftNumber < rightNumber
    default:
      throw ExecStepError(
        failure: ExecFailure(
          stepPath: path, op: op, code: "badParameter",
          message: "unknown condition op \(condition.op)"))
    }
  }

  private func encodeJSON<T: Encodable>(_ value: T) throws -> JSONValue {
    try AgentProcedureCodec.encodeResult(value)
  }

  private func execContextJSON(_ info: BrowserContextInfo) -> JSONValue {
    .object([
      "id": .number(Double(info.id.rawValue)), "name": .string(info.name),
      "pageCount": .number(Double(info.pageCount)),
    ])
  }

  private func execPageJSON(_ info: BrowserPageInfo) -> JSONValue {
    var object: [String: JSONValue] = [
      "id": .number(Double(info.id.rawValue)),
      "context": .number(Double(info.contextID.rawValue)),
      "title": .string(info.title),
      "loaded": .bool(info.loaded),
      "width": .number(info.viewport.width),
      "height": .number(info.viewport.height),
      "historyIndex": .number(Double(info.historyIndex)),
      "historyCount": .number(Double(info.historyCount)),
      "canGoBack": .bool(info.canGoBack),
      "canGoForward": .bool(info.canGoForward),
    ]
    if let url = info.url { object["url"] = .string(url.absoluteString) }
    return .object(object)
  }

  private func execNodeJSON(_ node: InspectedNode) -> JSONValue {
    var object: [String: JSONValue] = [
      "index": .number(Double(node.id.index)),
      "generation": .number(Double(node.id.version)),
      "role": .string(node.role),
      "name": .string(node.name),
      "enabled": .bool(node.enabled),
      "editable": .bool(node.editable),
      "visible": .bool(node.visible),
    ]
    if let value = node.value { object["value"] = .string(value) }
    if let href = node.href { object["href"] = .string(href) }
    return .object(object)
  }
}

struct ExecStepError: Error, Sendable {
  let failure: ExecFailure
}

enum ExecDeadline: Error {
  case exceeded
}

extension ExecStep {
  var intoTarget: String? {
    switch self {
    case .createContext(_, let into): return into
    case .createPage(_, _, _, let into): return into
    case .query(_, _, let into): return into
    case .queryAll(_, _, let into): return into
    case .evaluate(_, _, let into): return into
    case .restore(_, let into): return into
    case .snapshot(_, _, let into): return into
    case .inspect(_, let into): return into
    default: return nil
    }
  }
}

extension ExecValue {
  func resolve(_ vars: [String: JSONValue]) throws -> JSONValue {
    switch self {
    case .literal(let value): return value
    case .ref(let path): return try resolveRef(path, vars: vars)
    }
  }

  func stringValue(
    _ vars: [String: JSONValue], what: String, path: [Int] = [], op: String = "exec"
  ) throws -> String {
    let value = try resolve(vars)
    guard let text = value.string else {
      throw ExecStepError(
        failure: ExecFailure(
          stepPath: path, op: op, code: "typeMismatch",
          message: "\(what) must be a string"))
    }
    return text
  }

  func uint64Value(
    _ vars: [String: JSONValue], what: String, path: [Int] = [], op: String = "exec"
  ) throws -> UInt64 {
    let value = try resolve(vars)
    if let exact = value.exactUInt64 { return exact }
    guard let number = value.number, let exact = UInt64(exactly: number) else {
      throw ExecStepError(
        failure: ExecFailure(
          stepPath: path, op: op, code: "typeMismatch",
          message: "\(what) must be an integer id"))
    }
    return exact
  }
}

private func resolveRef(_ source: String, vars: [String: JSONValue]) throws -> JSONValue {
  let (name, segments) = try parseRef(source)
  guard let root = vars[name] else {
    throw ExecStepError(
      failure: ExecFailure(
        stepPath: [], op: "exec", code: "undefinedVariable",
        message: "Undefined variable $\(name)"))
  }
  var current = root
  for segment in segments {
    switch segment {
    case .field(let key):
      guard case .object(let object) = current, let next = object[key] else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: [], op: "exec", code: "badPath",
            message: "Path $\(source) has no field \(key)"))
      }
      current = next
    case .index(let position):
      guard case .array(let items) = current, items.indices.contains(position) else {
        throw ExecStepError(
          failure: ExecFailure(
            stepPath: [], op: "exec", code: "badPath",
            message: "Path $\(source) has no index \(position)"))
      }
      current = items[position]
    }
  }
  return current
}

private enum RefSegment {
  case field(String)
  case index(Int)
}

private func parseRef(_ source: String) throws -> (String, [RefSegment]) {
  func fail(_ message: String) -> ExecStepError {
    ExecStepError(
      failure: ExecFailure(stepPath: [], op: "exec", code: "badPath", message: message))
  }
  let scalars = Array(source)
  var position = 0
  func isStart(_ scalar: Character) -> Bool { scalar == "_" || scalar.isLetter }
  func isPart(_ scalar: Character) -> Bool { scalar == "_" || scalar.isLetter || scalar.isNumber }
  guard position < scalars.count, isStart(scalars[position]) else {
    throw fail("Invalid variable reference $\(source)")
  }
  var name = ""
  while position < scalars.count, isPart(scalars[position]) {
    name.append(scalars[position])
    position += 1
  }
  var segments: [RefSegment] = []
  while position < scalars.count {
    if scalars[position] == "." {
      position += 1
      guard position < scalars.count, isStart(scalars[position]) else {
        throw fail("Invalid variable reference $\(source)")
      }
      var field = ""
      while position < scalars.count, isPart(scalars[position]) {
        field.append(scalars[position])
        position += 1
      }
      segments.append(.field(field))
    } else if scalars[position] == "[" {
      position += 1
      var digits = ""
      while position < scalars.count, scalars[position].isNumber {
        digits.append(scalars[position])
        position += 1
      }
      guard !digits.isEmpty, position < scalars.count, scalars[position] == "]",
        let index = Int(digits)
      else {
        throw fail("Invalid variable reference $\(source)")
      }
      position += 1
      segments.append(.index(index))
    } else {
      throw fail("Invalid variable reference $\(source)")
    }
  }
  return (name, segments)
}

actor ExecRunState {
  private(set) var vars: [String: JSONValue] = [:]
  private var results: [JSONValue] = []
  private var failures: [ExecFailure] = []
  private var stepsExecuted = 0
  private var operations = 0
  private var revocationRequested = false

  /// Set by the runtime when the workspace lease authorizing this program ends. Checked at
  /// every step boundary, so revocation latency is one browser operation.
  func requestRevocation() {
    revocationRequested = true
  }

  func revocation() -> String? {
    revocationRequested
      ? "Workspace lease ended while this program was running"
      : nil
  }

  func noteStep() -> Int {
    stepsExecuted += 1
    return stepsExecuted
  }

  func noteOperation() {
    operations += 1
  }

  func noteFailure(_ failure: ExecFailure) {
    failures.append(failure)
  }

  func setVar(_ name: String, value: JSONValue) {
    vars[name] = value
  }

  func swapVar(_ name: String, value: JSONValue) -> JSONValue? {
    let previous = vars[name]
    vars[name] = value
    return previous
  }

  func restoreVar(_ name: String, value: JSONValue?) {
    vars[name] = value
  }

  func appendResult(_ value: JSONValue) {
    results.append(value)
  }

  func snapshot() -> ExecOutcome {
    ExecOutcome(
      executionID: "", status: .completed, results: results, vars: vars,
      stepsExecuted: stepsExecuted, operations: operations, failures: failures, error: nil)
  }
}
