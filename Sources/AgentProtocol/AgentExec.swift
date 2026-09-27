import Foundation

public enum ExecLimits {
  public static let programVersion = 1
  public static let maxSteps = 1_000
  public static let maxExecutedSteps = 100_000
  public static let maxItems = 10_000
  public static let defaultTimeoutMs: UInt64 = 30_000
  public static let maxTimeoutMs: UInt64 = 300_000
  public static let maxSnapshotLimit = 100_000
}

public enum ExecOnError: String, Hashable, Sendable, Codable {
  case stop
  case proceed
}

public enum ExecStatus: String, Hashable, Sendable, Codable {
  case completed
  case failed
  case timeout
  case cancelled
}

public struct ExecProgram: Hashable, Sendable, Codable {
  public var version: Int
  public var session: UInt64?
  public var timeoutMs: UInt64?
  public var onError: ExecOnError
  public var steps: [ExecStep]

  public init(
    version: Int = ExecLimits.programVersion,
    session: UInt64? = nil,
    timeoutMs: UInt64? = nil,
    onError: ExecOnError = .stop,
    steps: [ExecStep] = []
  ) {
    self.version = version
    self.session = session
    self.timeoutMs = timeoutMs
    self.onError = onError
    self.steps = steps
  }

  public func validate() throws {
    guard version == ExecLimits.programVersion else {
      throw AgentProcedureError(
        code: "badParameter", message: "unsupported exec program version \(version)")
    }
    guard steps.count >= 1 && steps.count <= ExecLimits.maxSteps else {
      throw AgentProcedureError(code: "badParameter", message: "steps")
    }
    if let timeoutMs {
      guard timeoutMs >= 1 && timeoutMs <= ExecLimits.maxTimeoutMs else {
        throw AgentProcedureError(code: "badParameter", message: "timeoutMs")
      }
    }
    var declared = 0
    try validate(steps: steps, declared: &declared)
  }

  private func validate(steps: [ExecStep], declared: inout Int) throws {
    for step in steps {
      declared += 1
      guard declared <= ExecLimits.maxSteps else {
        throw AgentProcedureError(code: "badParameter", message: "steps")
      }
      try step.validate()
      switch step {
      case .forEach(_, _, _, let limit, let nested):
        if let limit {
          guard limit >= 1 && limit <= ExecLimits.maxItems else {
            throw AgentProcedureError(code: "badParameter", message: "forEach.limit")
          }
        }
        try validate(steps: nested, declared: &declared)
      case .conditional(_, let then, let otherwise):
        try validate(steps: then, declared: &declared)
        try validate(steps: otherwise ?? [], declared: &declared)
      default:
        break
      }
    }
  }
}

public enum ExecValue: Hashable, Sendable, Codable {
  case literal(JSONValue)
  case ref(String)

  public init(from decoder: Decoder) throws {
    let value = try JSONValue(from: decoder)
    if case .object(let object) = value, object.count == 1 {
      if let name = object["ref"]?.string {
        self = .ref(name)
        return
      }
      if let nested = object["literal"] {
        self = .literal(nested)
        return
      }
    }
    self = .literal(value)
  }

  public func encode(to encoder: Encoder) throws {
    switch self {
    case .literal(let value):
      try value.encode(to: encoder)
    case .ref(let name):
      try JSONValue.object(["ref": .string(name)]).encode(to: encoder)
    }
  }
}

public struct ExecCondition: Hashable, Sendable, Codable {
  public var op: String
  public var left: ExecValue
  public var right: ExecValue?

  public init(op: String, left: ExecValue, right: ExecValue? = nil) {
    self.op = op
    self.left = left
    self.right = right
  }
}

public enum ExecStep: Hashable, Sendable, Codable {
  case createContext(name: ExecValue, into: String?)
  case createPage(context: ExecValue, width: Double?, height: Double?, into: String?)
  case navigate(page: ExecValue, url: ExecValue, settle: String?)
  case loadHTML(page: ExecValue, html: ExecValue, url: ExecValue)
  case query(page: ExecValue, selector: ExecValue, into: String?)
  case queryAll(page: ExecValue, selector: ExecValue, into: String?)
  case click(page: ExecValue, index: ExecValue, generation: ExecValue)
  case type(
    page: ExecValue, index: ExecValue, generation: ExecValue, text: ExecValue, append: Bool?)
  case evaluate(page: ExecValue, source: ExecValue, into: String?)
  case snapshot(page: ExecValue, limit: Int?, into: String?)
  case inspect(page: ExecValue, into: String?)
  case wait(page: ExecValue, selector: ExecValue, condition: String?, timeoutMs: UInt64?)
  /// Activates a hibernated page (a page restored from a profile, including every page of
  /// a freshly forked branch) so later steps can drive it. `page.restore` in RPC form.
  case restore(page: ExecValue, into: String?)
  case set(name: String, value: ExecValue)
  case assert(condition: ExecCondition, message: String?)
  case forEach(items: ExecValue, item: String, index: String?, limit: Int?, steps: [ExecStep])
  case conditional(condition: ExecCondition, then: [ExecStep], otherwise: [ExecStep]?)
  case result(value: ExecValue)

  public var op: String {
    switch self {
    case .createContext: return "createContext"
    case .createPage: return "createPage"
    case .navigate: return "navigate"
    case .loadHTML: return "loadHTML"
    case .query: return "query"
    case .queryAll: return "queryAll"
    case .click: return "click"
    case .type: return "type"
    case .evaluate: return "evaluate"
    case .snapshot: return "snapshot"
    case .inspect: return "inspect"
    case .wait: return "wait"
    case .restore: return "restore"
    case .set: return "set"
    case .assert: return "assert"
    case .forEach: return "forEach"
    case .conditional: return "if"
    case .result: return "result"
    }
  }

  public func validate() throws {
    switch self {
    case .snapshot(_, let limit, _):
      if let limit {
        guard limit >= 1 && limit <= ExecLimits.maxSnapshotLimit else {
          throw AgentProcedureError(code: "badParameter", message: "snapshot.limit")
        }
      }
    case .wait(_, _, _, let timeoutMs):
      if let timeoutMs {
        guard timeoutMs >= 1 && timeoutMs <= ExecLimits.maxTimeoutMs else {
          throw AgentProcedureError(code: "badParameter", message: "wait.timeoutMs")
        }
      }
    case .forEach(_, let item, let index, _, let steps):
      guard !item.isEmpty, steps.count >= 1 else {
        throw AgentProcedureError(code: "badParameter", message: "forEach")
      }
      if let index { guard !index.isEmpty else {
        throw AgentProcedureError(code: "badParameter", message: "forEach.index") } }
    case .conditional(_, let then, _):
      guard then.count >= 1 else {
        throw AgentProcedureError(code: "badParameter", message: "if.then")
      }
    case .set(let name, _):
      guard !name.isEmpty else {
        throw AgentProcedureError(code: "badParameter", message: "set.name")
      }
    default:
      break
    }
  }

  private enum CodingKeys: String, CodingKey {
    case op, name, context, page, url, html, selector, index, generation, text, append,
      source, into, limit, condition, timeoutMs, value, message, items, item, steps,
      then, otherwise, width, height, settle, left, right
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let op = try container.decode(String.self, forKey: .op)
    switch op {
    case "createContext":
      self = .createContext(
        name: try container.decode(ExecValue.self, forKey: .name),
        into: try container.decodeIfPresent(String.self, forKey: .into))
    case "createPage":
      self = .createPage(
        context: try container.decode(ExecValue.self, forKey: .context),
        width: try container.decodeIfPresent(Double.self, forKey: .width),
        height: try container.decodeIfPresent(Double.self, forKey: .height),
        into: try container.decodeIfPresent(String.self, forKey: .into))
    case "navigate":
      self = .navigate(
        page: try container.decode(ExecValue.self, forKey: .page),
        url: try container.decode(ExecValue.self, forKey: .url),
        settle: try container.decodeIfPresent(String.self, forKey: .settle))
    case "loadHTML":
      self = .loadHTML(
        page: try container.decode(ExecValue.self, forKey: .page),
        html: try container.decode(ExecValue.self, forKey: .html),
        url: try container.decode(ExecValue.self, forKey: .url))
    case "query":
      self = .query(
        page: try container.decode(ExecValue.self, forKey: .page),
        selector: try container.decode(ExecValue.self, forKey: .selector),
        into: try container.decodeIfPresent(String.self, forKey: .into))
    case "queryAll":
      self = .queryAll(
        page: try container.decode(ExecValue.self, forKey: .page),
        selector: try container.decode(ExecValue.self, forKey: .selector),
        into: try container.decodeIfPresent(String.self, forKey: .into))
    case "click":
      self = .click(
        page: try container.decode(ExecValue.self, forKey: .page),
        index: try container.decode(ExecValue.self, forKey: .index),
        generation: try container.decode(ExecValue.self, forKey: .generation))
    case "type":
      self = .type(
        page: try container.decode(ExecValue.self, forKey: .page),
        index: try container.decode(ExecValue.self, forKey: .index),
        generation: try container.decode(ExecValue.self, forKey: .generation),
        text: try container.decode(ExecValue.self, forKey: .text),
        append: try container.decodeIfPresent(Bool.self, forKey: .append))
    case "evaluate":
      self = .evaluate(
        page: try container.decode(ExecValue.self, forKey: .page),
        source: try container.decode(ExecValue.self, forKey: .source),
        into: try container.decodeIfPresent(String.self, forKey: .into))
    case "snapshot":
      self = .snapshot(
        page: try container.decode(ExecValue.self, forKey: .page),
        limit: try container.decodeIfPresent(Int.self, forKey: .limit),
        into: try container.decodeIfPresent(String.self, forKey: .into))
    case "inspect":
      self = .inspect(
        page: try container.decode(ExecValue.self, forKey: .page),
        into: try container.decodeIfPresent(String.self, forKey: .into))
    case "wait":
      self = .wait(
        page: try container.decode(ExecValue.self, forKey: .page),
        selector: try container.decode(ExecValue.self, forKey: .selector),
        condition: try container.decodeIfPresent(String.self, forKey: .condition),
        timeoutMs: try container.decodeIfPresent(UInt64.self, forKey: .timeoutMs))
    case "restore":
      self = .restore(
        page: try container.decode(ExecValue.self, forKey: .page),
        into: try container.decodeIfPresent(String.self, forKey: .into))
    case "set":
      self = .set(
        name: try container.decode(String.self, forKey: .name),
        value: try container.decode(ExecValue.self, forKey: .value))
    case "assert":
      self = .assert(
        condition: try container.decode(ExecCondition.self, forKey: .condition),
        message: try container.decodeIfPresent(String.self, forKey: .message))
    case "forEach":
      self = .forEach(
        items: try container.decode(ExecValue.self, forKey: .items),
        item: try container.decode(String.self, forKey: .item),
        index: try container.decodeIfPresent(String.self, forKey: .index),
        limit: try container.decodeIfPresent(Int.self, forKey: .limit),
        steps: try container.decode([ExecStep].self, forKey: .steps))
    case "if":
      self = .conditional(
        condition: try container.decode(ExecCondition.self, forKey: .condition),
        then: try container.decode([ExecStep].self, forKey: .then),
        otherwise: try container.decodeIfPresent([ExecStep].self, forKey: .otherwise))
    case "result":
      self = .result(value: try container.decode(ExecValue.self, forKey: .value))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .op, in: container, debugDescription: "unknown exec op \(op)")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(op, forKey: .op)
    switch self {
    case .createContext(let name, let into):
      try container.encode(name, forKey: .name)
      try container.encodeIfPresent(into, forKey: .into)
    case .createPage(let context, let width, let height, let into):
      try container.encode(context, forKey: .context)
      try container.encodeIfPresent(width, forKey: .width)
      try container.encodeIfPresent(height, forKey: .height)
      try container.encodeIfPresent(into, forKey: .into)
    case .navigate(let page, let url, let settle):
      try container.encode(page, forKey: .page)
      try container.encode(url, forKey: .url)
      try container.encodeIfPresent(settle, forKey: .settle)
    case .loadHTML(let page, let html, let url):
      try container.encode(page, forKey: .page)
      try container.encode(html, forKey: .html)
      try container.encode(url, forKey: .url)
    case .query(let page, let selector, let into):
      try container.encode(page, forKey: .page)
      try container.encode(selector, forKey: .selector)
      try container.encodeIfPresent(into, forKey: .into)
    case .queryAll(let page, let selector, let into):
      try container.encode(page, forKey: .page)
      try container.encode(selector, forKey: .selector)
      try container.encodeIfPresent(into, forKey: .into)
    case .click(let page, let index, let generation):
      try container.encode(page, forKey: .page)
      try container.encode(index, forKey: .index)
      try container.encode(generation, forKey: .generation)
    case .type(let page, let index, let generation, let text, let append):
      try container.encode(page, forKey: .page)
      try container.encode(index, forKey: .index)
      try container.encode(generation, forKey: .generation)
      try container.encode(text, forKey: .text)
      try container.encodeIfPresent(append, forKey: .append)
    case .evaluate(let page, let source, let into):
      try container.encode(page, forKey: .page)
      try container.encode(source, forKey: .source)
      try container.encodeIfPresent(into, forKey: .into)
    case .snapshot(let page, let limit, let into):
      try container.encode(page, forKey: .page)
      try container.encodeIfPresent(limit, forKey: .limit)
      try container.encodeIfPresent(into, forKey: .into)
    case .inspect(let page, let into):
      try container.encode(page, forKey: .page)
      try container.encodeIfPresent(into, forKey: .into)
    case .wait(let page, let selector, let condition, let timeoutMs):
      try container.encode(page, forKey: .page)
      try container.encode(selector, forKey: .selector)
      try container.encodeIfPresent(condition, forKey: .condition)
      try container.encodeIfPresent(timeoutMs, forKey: .timeoutMs)
    case .restore(let page, let into):
      try container.encode(page, forKey: .page)
      try container.encodeIfPresent(into, forKey: .into)
    case .set(let name, let value):
      try container.encode(name, forKey: .name)
      try container.encode(value, forKey: .value)
    case .assert(let condition, let message):
      try container.encode(condition, forKey: .condition)
      try container.encodeIfPresent(message, forKey: .message)
    case .forEach(let items, let item, let index, let limit, let steps):
      try container.encode(items, forKey: .items)
      try container.encode(item, forKey: .item)
      try container.encodeIfPresent(index, forKey: .index)
      try container.encodeIfPresent(limit, forKey: .limit)
      try container.encode(steps, forKey: .steps)
    case .conditional(let condition, let then, let otherwise):
      try container.encode(condition, forKey: .condition)
      try container.encode(then, forKey: .then)
      try container.encodeIfPresent(otherwise, forKey: .otherwise)
    case .result(let value):
      try container.encode(value, forKey: .value)
    }
  }
}

public struct ExecFailure: Hashable, Sendable, Codable {
  /// Failure code used when the workspace lease authorizing a program ends mid-flight.
  /// Never swallowed by `onError: proceed`; the program terminates as `cancelled`.
  public static let leaseRevokedCode = "leaseRevoked"

  public var stepPath: [Int]
  public var op: String
  public var code: String
  public var message: String

  public init(stepPath: [Int], op: String, code: String, message: String) {
    self.stepPath = stepPath
    self.op = op
    self.code = code
    self.message = message
  }
}

public struct ExecOutcome: Hashable, Sendable, Codable {
  public var executionID: String
  public var status: ExecStatus
  public var results: [JSONValue]
  public var vars: [String: JSONValue]
  public var stepsExecuted: Int
  public var operations: Int
  public var failures: [ExecFailure]
  public var error: ExecFailure?

  public init(
    executionID: String,
    status: ExecStatus,
    results: [JSONValue] = [],
    vars: [String: JSONValue] = [:],
    stepsExecuted: Int = 0,
    operations: Int = 0,
    failures: [ExecFailure] = [],
    error: ExecFailure? = nil
  ) {
    self.executionID = executionID
    self.status = status
    self.results = results
    self.vars = vars
    self.stepsExecuted = stepsExecuted
    self.operations = operations
    self.failures = failures
    self.error = error
  }
}

public enum AgentExec: AgentProcedure {
  public static let method: AgentMethod = .exec

  public struct Input: Codable, Sendable, Hashable {
    public let program: ExecProgram
    public let timeoutMs: UInt64?

    public init(program: ExecProgram, timeoutMs: UInt64? = nil) {
      self.program = program
      self.timeoutMs = timeoutMs
    }

    public func validate() throws {
      if let timeoutMs {
        guard timeoutMs >= 1 && timeoutMs <= ExecLimits.maxTimeoutMs else {
          throw AgentProcedureError(code: "badParameter", message: "timeoutMs")
        }
      }
      try program.validate()
    }
  }

  public typealias Output = ExecOutcome
}
