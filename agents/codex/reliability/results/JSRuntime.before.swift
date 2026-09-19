import DOM
import Foundation
import Storage

public enum JSError: Error, CustomStringConvertible {
  case syntax(String)
  case reference(String)
  case type(String)
  case range(String)
  case runtime(String)
  case thrown(JSValue)

  public var description: String {
    switch self {
    case .syntax(let value): return "SyntaxError: \(value)"
    case .reference(let value): return "ReferenceError: \(value)"
    case .type(let value): return "TypeError: \(value)"
    case .range(let value): return "RangeError: \(value)"
    case .runtime(let value): return "RuntimeError: \(value)"
    case .thrown(let value): return "Uncaught \(value)"
    }
  }
}

public indirect enum JSValue: CustomStringConvertible, Equatable {
  case number(Double)
  case bigint(String)
  case string(String)
  case bool(Bool)
  case symbol(Int)
  case null
  case undefined
  case object(JSObject)
  case function(JSFunction)

  public static func == (lhs: JSValue, rhs: JSValue) -> Bool {
    switch (lhs, rhs) {
    case (.number(let a), .number(let b)): return a == b
    case (.bigint(let a), .bigint(let b)): return a == b
    case (.string(let a), .string(let b)): return a == b
    case (.bool(let a), .bool(let b)): return a == b
    case (.symbol(let a), .symbol(let b)): return a == b
    case (.null, .null), (.undefined, .undefined): return true
    case (.object(let a), .object(let b)): return a === b
    case (.function(let a), .function(let b)): return a === b
    default: return false
    }
  }

  public var description: String {
    switch self {
    case .number(let value):
      if value.isNaN { return "NaN" }
      if value.isInfinite { return value > 0 ? "Infinity" : "-Infinity" }
      if value == 0 { return "0" }
      if value.rounded() == value && abs(value) < 1e21 { return String(Int64(value)) }
      return String(value)
    case .bigint(let text): return text
    case .string(let value): return value
    case .bool(let value): return value ? "true" : "false"
    case .symbol(let id): return "Symbol(\(id))"
    case .null: return "null"
    case .undefined: return "undefined"
    case .object(let object): return object.description
    case .function(let function): return function.description
    }
  }

  public var truthy: Bool {
    switch self {
    case .undefined, .null: return false
    case .bool(let value): return value
    case .number(let value): return value != 0 && !value.isNaN
    case .bigint(let text): return text != "0"
    case .string(let value): return !value.isEmpty
    case .symbol: return true
    case .object, .function: return true
    }
  }

  public var isNullish: Bool {
    if case .null = self { return true }
    if case .undefined = self { return true }
    return false
  }
}

public struct JSPropertyAttributes: Sendable {
  public var writable: Bool
  public var enumerable: Bool
  public var configurable: Bool

  public init(writable: Bool = true, enumerable: Bool = true, configurable: Bool = true) {
    self.writable = writable
    self.enumerable = enumerable
    self.configurable = configurable
  }

  public static let `default` = JSPropertyAttributes()
}

public final class JSObject: CustomStringConvertible {
  public var properties: [String: JSValue]
  public var attributes: [String: JSPropertyAttributes]
  public var accessorGet: [String: JSFunction]
  public var accessorSet: [String: JSFunction]
  public var symbolProperties: [Int: JSValue]
  public var prototype: JSObject?
  public var nativeGet: ((String) -> JSValue?)?
  public var nativeSet: ((String, JSValue) -> Bool)?
  public var nativeNodeID: NodeID?
  public var promiseState: JSPromiseState?
  public var isArrayBuffer: Bool
  public var arrayBufferData: Data?
  public var typedArrayKind: String?
  public var typedArrayOffset: Int
  public var typedArrayLength: Int
  public var typedArrayBuffer: JSObject?
  public var mapEntries: [(key: JSValue, value: JSValue)]?
  public var setValues: [JSValue]?
  public var isExtensible = true
  public var headerFields: [(name: String, value: String)]?
  public var isFetchRequest = false
  public var requestMethod = "GET"
  public var requestURL = ""
  public var requestBody: Data?
  public var isFetchResponse = false
  public var responseStatus = 0
  public var responseStatusText = ""
  public var responseURL = ""
  public var responseBody: Data?

  public init(
    properties: [String: JSValue] = [:], nativeGet: ((String) -> JSValue?)? = nil,
    nativeSet: ((String, JSValue) -> Bool)? = nil, nativeNodeID: NodeID? = nil,
    prototype: JSObject? = nil
  ) {
    self.properties = properties
    self.attributes = [:]
    self.accessorGet = [:]
    self.accessorSet = [:]
    self.symbolProperties = [:]
    self.prototype = prototype
    self.nativeGet = nativeGet
    self.nativeSet = nativeSet
    self.nativeNodeID = nativeNodeID
    self.promiseState = nil
    self.isArrayBuffer = false
    self.arrayBufferData = nil
    self.typedArrayKind = nil
    self.typedArrayOffset = 0
    self.typedArrayLength = 0
    self.typedArrayBuffer = nil
  }

  public func get(_ key: String) -> JSValue {
    if let native = nativeGet?(key) { return native }
    var current: JSObject? = self
    var visited = Set<ObjectIdentifier>()
    while let object = current {
      let id = ObjectIdentifier(object)
      if visited.contains(id) { break }
      visited.insert(id)
      if let value = object.properties[key] { return value }
      current = object.prototype
    }
    return .undefined
  }

  public func set(_ key: String, _ value: JSValue) {
    if nativeSet?(key, value) == true { return }
    properties[key] = value
  }

  public func hasOwn(_ key: String) -> Bool { properties[key] != nil }

  @discardableResult
  public func deleteOwn(_ key: String) -> Bool {
    if attributes[key]?.configurable == false { return false }
    attributes.removeValue(forKey: key)
    accessorGet.removeValue(forKey: key)
    accessorSet.removeValue(forKey: key)
    return properties.removeValue(forKey: key) != nil
  }

  public func ownEnumerableKeys() -> [String] {
    properties.keys.filter { attributes[$0]?.enumerable ?? true }
  }

  public var description: String {
    let pairs = properties.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }
    return "{\(pairs.joined(separator: ", "))}"
  }
}

public final class JSFunction: CustomStringConvertible {
  public let parameters: [JSPattern]
  public let body: [JSStatement]?
  public let arrowBody: JSArrowBody?
  public let closure: JSEnvironment?
  public let native: (([JSValue]) throws -> JSValue)?
  public let nativeMethod: ((JSValue, [JSValue]) throws -> JSValue)?
  public var name: String
  public var isAsync: Bool
  public var isArrow: Bool
  public var isClass: Bool
  public var isMethod: Bool
  public var homeObject: JSObject?
  public var superclass: JSFunction?
  public var staticProperties = JSObject()
  public var instanceFields: [(String, JSExpression?)]
  public var capturedThis: JSValue?
  public var prototypeObject: JSObject?
  public var boundTarget: JSFunction?
  public var boundThis: JSValue?
  public var boundArguments: [JSValue]
  public var constructNative: (([JSValue]) throws -> JSValue)?

  public init(
    parameters: [String], body: [JSStatement], closure: JSEnvironment?,
    name: String = "", isAsync: Bool = false
  ) {
    self.parameters = parameters.map { .identifier($0, nil) }
    self.body = body
    self.arrowBody = nil
    self.closure = closure
    self.native = nil
    self.nativeMethod = nil
    self.name = name
    self.isAsync = isAsync
    self.isArrow = false
    self.isClass = false
    self.isMethod = false
    self.homeObject = nil
    self.superclass = nil
    self.instanceFields = []
    self.capturedThis = nil
    self.prototypeObject = nil
    self.boundTarget = nil
    self.boundThis = nil
    self.boundArguments = []
  }

  public init(
    patterns: [JSPattern], body: [JSStatement], closure: JSEnvironment?,
    name: String = "", isAsync: Bool = false, isArrow: Bool = false,
    arrowBody: JSArrowBody? = nil
  ) {
    self.parameters = patterns
    self.body = body
    self.arrowBody = arrowBody
    self.closure = closure
    self.native = nil
    self.nativeMethod = nil
    self.name = name
    self.isAsync = isAsync
    self.isArrow = isArrow
    self.isClass = false
    self.isMethod = false
    self.homeObject = nil
    self.superclass = nil
    self.instanceFields = []
    self.capturedThis = nil
    self.prototypeObject = nil
    self.boundTarget = nil
    self.boundThis = nil
    self.boundArguments = []
  }

  public init(
    native: @escaping ([JSValue]) throws -> JSValue, name: String = ""
  ) {
    parameters = []
    body = nil
    arrowBody = nil
    closure = nil
    self.native = native
    self.nativeMethod = nil
    self.name = name
    self.isAsync = false
    self.isArrow = false
    self.isClass = false
    self.isMethod = false
    self.homeObject = nil
    self.superclass = nil
    self.instanceFields = []
    self.capturedThis = nil
    self.prototypeObject = nil
    self.boundTarget = nil
    self.boundThis = nil
    self.boundArguments = []
  }

  public init(
    nativeMethod: @escaping (JSValue, [JSValue]) throws -> JSValue, name: String = ""
  ) {
    parameters = []
    body = nil
    arrowBody = nil
    closure = nil
    self.native = nil
    self.nativeMethod = nativeMethod
    self.name = name
    self.isAsync = false
    self.isArrow = false
    self.isClass = false
    self.isMethod = false
    self.homeObject = nil
    self.superclass = nil
    self.instanceFields = []
    self.capturedThis = nil
    self.prototypeObject = nil
    self.boundTarget = nil
    self.boundThis = nil
    self.boundArguments = []
  }

  public var description: String { "[Function\(name.isEmpty ? "" : ": \(name)")]}" }
}

public final class JSEnvironment {
  public enum Kind {
    case function
    case block
  }

  private var values: [String: JSValue]
  private var constantNames: Set<String>
  private var uninitialized: Set<String>
  public let parent: JSEnvironment?
  public let kind: Kind

  public init(
    parent: JSEnvironment? = nil, kind: Kind = .block, values: [String: JSValue] = [:]
  ) {
    self.parent = parent
    self.kind = kind
    self.values = values
    self.constantNames = []
    self.uninitialized = []
  }

  public func define(_ name: String, value: JSValue) { values[name] = value }

  public func get(_ name: String) -> JSValue? {
    if uninitialized.contains(name) { return nil }
    return values[name] ?? parent?.get(name)
  }

  public func checkedGet(_ name: String) throws -> JSValue {
    if uninitialized.contains(name) {
      throw JSError.reference("\(name) is not defined")
    }
    if let value = values[name] { return value }
    if let parent { return try parent.checkedGet(name) }
    throw JSError.reference("\(name) is not defined")
  }

  @discardableResult
  public func assign(_ name: String, value: JSValue) -> Bool {
    if uninitialized.contains(name) { return false }
    if values[name] != nil {
      if constantNames.contains(name) { return false }
      values[name] = value
      return true
    }
    return parent?.assign(name, value: value) ?? false
  }

  public func checkedAssign(_ name: String, value: JSValue, strict: Bool) throws {
    if uninitialized.contains(name) {
      throw JSError.reference("\(name) is not defined")
    }
    if values[name] != nil {
      if constantNames.contains(name) { throw JSError.type("Assignment to constant variable") }
      values[name] = value
      return
    }
    if let parent {
      try parent.checkedAssign(name, value: value, strict: strict)
      return
    }
    if strict { throw JSError.reference("\(name) is not defined") }
    values[name] = value
  }

  public func declareVariable(_ name: String) {
    if values[name] == nil && !uninitialized.contains(name) { values[name] = .undefined }
  }

  public func declareLexical(_ name: String, constant: Bool) throws {
    if values[name] != nil || uninitialized.contains(name) {
      throw JSError.syntax("Identifier \(name) has already been declared")
    }
    uninitialized.insert(name)
    if constant { constantNames.insert(name) }
  }

  public func initializeLexical(_ name: String, value: JSValue) throws {
    guard uninitialized.contains(name) else {
      if values[name] != nil {
        if constantNames.contains(name) { throw JSError.type("Assignment to constant variable") }
        values[name] = value
        return
      }
      throw JSError.reference("\(name) is not defined")
    }
    uninitialized.remove(name)
    values[name] = value
  }

  public func defineFunction(_ name: String, value: JSValue) {
    if uninitialized.contains(name) { uninitialized.remove(name) }
    constantNames.remove(name)
    values[name] = value
  }

  public func nearestVariableScope() -> JSEnvironment {
    var scope: JSEnvironment? = self
    while let current = scope {
      if current.kind == .function { return current }
      scope = current.parent
    }
    return self
  }

  public func hasOwnBinding(_ name: String) -> Bool {
    values[name] != nil || uninitialized.contains(name)
  }
}

public struct JSHostHooks {
  public var navigate: ((String) -> Void)?
  public var cookieString: (() -> String)?
  public var setCookieString: ((String) -> Void)?
  public var viewportSize: (() -> (Double, Double))?
  public var devicePixelRatio: (() -> Double)?
  public var userAgent: (() -> String)?
  public var currentURL: (() -> String)?
  public var mediaQueryHandler: ((String) -> Bool)?
  public var alertHandler: ((String) -> Void)?
  public var confirmHandler: ((String) -> Bool)?
  public var promptHandler: ((String, String) -> String?)?
  public var formSubmitHandler: ((NodeID) -> Void)?
  public var computedStyleHandler: ((NodeID, String) -> String?)?

  public init() {}
}

private enum Flow {
  case normal(JSValue)
  case returnValue(JSValue)
  case breakTarget(String?)
  case continueTarget(String?)
}

private enum JSReference {
  case variable(JSEnvironment, String)
  case property(JSValue, String)
  case symbolProperty(JSValue, Int)
}

final class CtorFrame {
  var fields: [(String, JSExpression?)]
  var instance: JSObject?

  init(fields: [(String, JSExpression?)]) {
    self.fields = fields
    self.instance = nil
  }
}

public final class JSRuntime {
  private let eventRegistry = JSEventRegistry()
  private weak var boundDocument: DOMDocument?
  public let globals: JSEnvironment
  public private(set) var consoleOutput: [String] = []
  public private(set) var unhandledRejections: [String] = []
  public var hostHooks = JSHostHooks()
  public var evalAllowed: () -> Bool = { true }
  public var stepBudget: Int = 4_000_000
  public private(set) var stepsUsed: Int = 0
  public let modules = JSModuleRegistry()
  public var timerHost: JSTimerHost?
  public let sessionStorage = LocalStorage()
  var domContext: JSDOMContext?
  public var asyncFetch:
    (@Sendable (String, String, [String: String], String?) async throws -> (
      Int, [String: String], Data
    ))?

  private let completionLock = NSLock()
  private var pendingCompletions: [@Sendable () -> Void] = []
  var fetchCapabilities: [UInt64: JSPromiseCapability] = [:]
  var nextFetchCapabilityID: UInt64 = 1

  private var microtasks: [() -> Void] = []
  private var thisStack: [JSValue] = []
  private var superStack: [JSObject?] = []
  private var superConstructorStack: [JSFunction?] = []
  private var ctorFieldStack: [CtorFrame] = []
  private var asyncDepth = 0
  private var strictDepth = 0
  private var chainShortCircuited = false
  private var labelStack: [String] = []
  private var symbolCounter = 0
  public var symbolDescriptions: [Int: String] = [:]
  public var symbolForRegistry: [String: Int] = [:]
  private var activeModule: JSModuleRecord?

  public func newSymbol(description: String?) -> JSValue {
    symbolCounter += 1
    let id = symbolCounter
    if let description { symbolDescriptions[id] = description }
    return .symbol(id)
  }

  public var objectPrototype = JSObject()
  public var arrayPrototype = JSObject()
  public var stringPrototype = JSObject()
  public var numberPrototype = JSObject()
  public var booleanPrototype = JSObject()
  public var functionPrototype = JSObject()
  public var errorPrototype = JSObject()
  public var regexpPrototype = JSObject()
  public var promisePrototype = JSObject()
  public var mapPrototype = JSObject()
  public var setPrototype = JSObject()
  public var arrayBufferPrototype = JSObject()
  public var typedArrayPrototype = JSObject()
  public var dataViewPrototype = JSObject()
  public var datePrototype = JSObject()
  public var symbolPrototype = JSObject()
  public var headersPrototype = JSObject()
  public var requestPrototype = JSObject()
  public var responsePrototype = JSObject()
  public var errorConstructors: [String: JSFunction] = [:]
  public var regexpConstructor: JSFunction?
  public var typedArrayKindPrototypes: [String: JSObject] = [:]
  public var globalObject = JSObject()

  public init(document: DOMDocument? = nil, localStorage: LocalStorage? = nil) {
    globals = JSEnvironment(parent: nil, kind: .function)
    boundDocument = document
    installBuiltins(document: document, localStorage: localStorage)
    eventRegistry.dispatch = { [weak self] event, target in
      self?.dispatchSyntheticEvent(event, target: target) ?? false
    }
  }

  public func evaluate(_ source: String) throws -> JSValue {
    let program = try JSParser(source: source).parseProgram()
    let result = try runStatements(program, module: nil)
    drainCompletions()
    drainMicrotasks()
    return result
  }

  public func evaluateModule(_ source: String, path: String) throws -> JSValue {
    let record = modules.record(for: path)
    let program = try JSParser(source: source).parseProgram()
    let result = try runStatements(program, module: record)
    drainCompletions()
    drainMicrotasks()
    return result
  }

  private func runStatements(_ program: [JSStatement], module: JSModuleRecord?) throws -> JSValue {
    stepsUsed = 0
    microtasks.removeAll(keepingCapacity: true)
    let scope = JSEnvironment(parent: globals, kind: .function)
    let previous = activeModule
    activeModule = module
    defer { activeModule = previous }
    thisStack.append(.object(globalObject))
    defer { _ = thisStack.popLast() }
    try hoist(program, in: scope)
    var last: JSValue = .undefined
    for statement in program {
      let flow = try execute(statement, environment: scope)
      switch flow {
      case .normal(let value): last = value
      case .returnValue(let value): last = value
      case .breakTarget, .continueTarget:
        throw JSError.syntax("Illegal break or continue outside a loop")
      }
    }
    drainMicrotasks()
    return last
  }

  public func runScripts(_ sources: [String]) -> [String] {
    var errors: [String] = []
    for source in sources {
      do { _ = try evaluate(source) } catch {
        errors.append(String(describing: error))
      }
    }
    return errors
  }

  public func queueMicrotask(_ task: @escaping () -> Void) {
    microtasks.append(task)
  }

  func enqueueCompletion(_ work: @escaping @Sendable () -> Void) {
    completionLock.lock()
    pendingCompletions.append(work)
    completionLock.unlock()
  }

  public func drainCompletions() {
    var iterations = 0
    while iterations < 10000 {
      iterations += 1
      completionLock.lock()
      let batch = pendingCompletions
      pendingCompletions.removeAll(keepingCapacity: true)
      completionLock.unlock()
      if batch.isEmpty { return }
      for work in batch { work() }
    }
  }

  public func invokeTimerCallback(_ callback: JSFunction) {
    do {
      _ = try callFunction(callback, arguments: [])
    } catch {
      consoleOutput.append("Uncaught \(String(describing: error))")
    }
    drainCompletions()
    drainMicrotasks()
  }

  @discardableResult
  public func pumpTimers(now: Double = Date().timeIntervalSince1970 * 1000) -> Int {
    let fired = (timerHost as? JSPumpableTimers)?.pump(now: now) ?? 0
    if fired > 0 {
      drainCompletions()
      drainMicrotasks()
    }
    return fired
  }

  public var hasPendingMicrotasks: Bool { !microtasks.isEmpty }

  public var pendingFetchCount: Int { fetchCapabilities.count }

  public func drainMicrotasks() {
    var iterations = 0
    while !microtasks.isEmpty && iterations < 100000 {
      iterations += 1
      let batch = microtasks
      microtasks.removeAll(keepingCapacity: true)
      for task in batch { task() }
    }
  }

  public func newCapability() -> JSPromiseCapability { JSPromiseCapability(runtime: self) }

  func settleCapability(_ capability: JSPromiseCapability, fulfilled value: JSValue) {
    if case .object(let object) = value, object.promiseState != nil {
      object.promiseState?.onSettled(
        fulfill: { [weak self] inner in
          self?.settleCapability(capability, fulfilled: inner)
        },
        reject: { [weak self] reason in
          self?.settleCapability(capability, rejected: reason)
        })
      return
    }
    capability.settleFulfilled(value)
  }

  func settleCapability(_ capability: JSPromiseCapability, rejected reason: JSValue) {
    capability.settleRejected(reason)
  }

  func reportUnhandledRejection(_ reason: JSValue) {
    unhandledRejections.append(reason.description)
  }

  func callTimerHost(milliseconds: Double, repeats: Bool, callback: JSFunction) throws -> Double {
    guard let host = timerHost else {
      throw JSError.runtime("Timers are not available in this context")
    }
    return host.setTimeout(milliseconds: milliseconds, repeats: repeats, callback: callback)
  }

  func clearTimerHost(id: Double) {
    timerHost?.clearTimeout(id: id)
  }

  public func callFunction(
    _ function: JSFunction, arguments: [JSValue], thisValue: JSValue = .undefined
  ) throws -> JSValue {
    try callValue(.function(function), thisValue: thisValue, arguments: arguments, env: nil)
  }

  public func callValue(
    _ callee: JSValue, thisValue: JSValue, arguments: [JSValue], env: JSEnvironment? = nil
  ) throws -> JSValue {
    var target = callee
    var receiver = thisValue
    var prepended: [JSValue] = []
    if case .function(let bound) = target, let inner = bound.boundTarget {
      target = .function(inner)
      receiver = bound.boundThis ?? .undefined
      prepended = bound.boundArguments
    }
    guard case .function(let function) = target else {
      throw JSError.type("Value is not callable")
    }
    if let nativeMethod = function.nativeMethod {
      return try nativeMethod(receiver, prepended + arguments)
    }
    if let native = function.native {
      return try native(prepended + arguments)
    }
    guard let body = function.body, let closure = function.closure else {
      return .undefined
    }
    if function.isAsync {
      let capability = JSPromiseCapability(runtime: self)
      do {
        let result = try runInterpreted(
          function: function, body: body, closure: closure, arguments: prepended + arguments,
          receiver: receiver, callingEnv: env)
        capability.resolve(result)
      } catch let error as JSError {
        capability.reject(errorValue(for: error))
      } catch {
        capability.reject(.string(error.localizedDescription))
      }
      return capability.promise
    }
    return try runInterpreted(
      function: function, body: body, closure: closure, arguments: prepended + arguments,
      receiver: receiver, callingEnv: env)
  }

  private func runInterpreted(
    function: JSFunction, body: [JSStatement], closure: JSEnvironment?,
    arguments: [JSValue], receiver: JSValue, callingEnv: JSEnvironment?
  ) throws -> JSValue {
    let scope = JSEnvironment(parent: closure, kind: .function)
    let effectiveThis: JSValue
    if function.isArrow {
      effectiveThis = function.capturedThis ?? .undefined
    } else {
      effectiveThis = receiver
    }
    thisStack.append(effectiveThis)
    let pushedSuper = function.homeObject?.prototype ?? nil
    superStack.append(pushedSuper)
    superConstructorStack.append(function.superclass)
    let pushedAsync = function.isAsync
    let wasAsync = asyncDepth > 0
    if pushedAsync { asyncDepth += 1 }
    defer {
      _ = thisStack.popLast()
      _ = superStack.popLast()
      _ = superConstructorStack.popLast()
      if pushedAsync && !wasAsync { asyncDepth = 0 } else if pushedAsync { asyncDepth -= 1 }
    }
    var index = 0
    for pattern in function.parameters {
      if case .rest(let name) = pattern {
        let rest = makeArray(Array(arguments.dropFirst(index)))
        scope.define(name, value: .object(rest))
        index = arguments.count
        break
      }
      let value = index < arguments.count ? arguments[index] : .undefined
      try bindPattern(pattern, value: value, environment: scope, kind: .parameter)
      index += 1
    }
    if !function.isArrow {
      let argsObject = JSObject(prototype: objectPrototype)
      for (offset, value) in arguments.enumerated() {
        argsObject.set(String(offset), value)
      }
      argsObject.set("length", .number(Double(arguments.count)))
      scope.define("arguments", value: .object(argsObject))
    }
    if let arrowBody = function.arrowBody, case .expression(let expression) = arrowBody {
      do {
        return try evaluate(expression, environment: scope)
      } catch let error as JSError where isReturnEscape(error) {
        throw error
      }
    }
    try hoist(body, in: scope)
    let flow = try executeList(body, environment: scope)
    switch flow {
    case .normal: return .undefined
    case .returnValue(let value): return value
    case .breakTarget, .continueTarget:
      throw JSError.syntax("Illegal break or continue inside function")
    }
  }

  private func isReturnEscape(_ error: JSError) -> Bool { false }

  func construct(
    _ callee: JSValue, arguments: [JSValue], env: JSEnvironment? = nil
  ) throws -> JSValue {
    var target = callee
    if case .function(let bound) = target, let inner = bound.boundTarget {
      var combined = bound.boundArguments
      combined.append(contentsOf: arguments)
      return try construct(.function(inner), arguments: combined, env: env)
    }
    guard case .function(let function) = target else {
      throw JSError.type("Value is not a constructor")
    }
    if let build = function.constructNative {
      return try build(arguments)
    }
    if let native = function.native {
      _ = native
      throw JSError.type("Value is not a constructor")
    }
    if function.isArrow || function.isMethod {
      throw JSError.type("Value is not a constructor")
    }
    if function.isClass {
      return try constructClass(function, arguments: arguments, env: env)
    }
    guard function.body != nil, function.closure != nil else {
      throw JSError.type("Value is not a constructor")
    }
    let instance = JSObject(prototype: function.prototypeObject ?? objectPrototype)
    let result = try runInterpreted(
      function: function, body: function.body ?? [], closure: function.closure,
      arguments: arguments, receiver: .object(instance), callingEnv: env)
    switch result {
    case .object: return result
    case .function: return result
    default: return .object(instance)
    }
  }

  private func constructClass(
    _ function: JSFunction, arguments: [JSValue], env: JSEnvironment?
  ) throws -> JSValue {
    let proto = function.prototypeObject ?? objectPrototype
    if let superclass = function.superclass {
      let frame = CtorFrame(fields: function.instanceFields)
      ctorFieldStack.append(frame)
      defer { _ = ctorFieldStack.popLast() }
      if let body = function.body, let closure = function.closure, !body.isEmpty {
        let scope = JSEnvironment(parent: closure, kind: .function)
        thisStack.append(.undefined)
        superStack.append(proto.prototype)
        superConstructorStack.append(superclass)
        if function.isAsync { asyncDepth += 1 }
        defer {
          _ = thisStack.popLast()
          _ = superStack.popLast()
          _ = superConstructorStack.popLast()
          if function.isAsync { asyncDepth -= 1 }
        }
        bindConstructorParams(function.parameters, arguments: arguments, scope: scope)
        if !function.isArrow {
          scope.define("arguments", value: .object(makeArray(arguments)))
        }
        try hoist(body, in: scope)
        let flow = try executeList(body, environment: scope)
        switch flow {
        case .normal: break
        case .returnValue(let value):
          switch value {
          case .object, .function: return value
          case .undefined: break
          default: break
          }
        case .breakTarget, .continueTarget:
          throw JSError.syntax("Illegal break or continue inside constructor")
        }
        guard let instance = frame.instance else {
          throw JSError.reference("Must call super constructor before using this")
        }
        return .object(instance)
      }
      let instance = JSObject(prototype: proto)
      if let build = superclass.constructNative {
        let nativeResult = try build(arguments)
        if case .object(let object) = nativeResult {
          object.prototype = proto
          try installInstanceFields(object, fields: function.instanceFields)
          return .object(object)
        }
        try installInstanceFields(instance, fields: function.instanceFields)
        return .object(instance)
      }
      let superResult = try runInterpreted(
        function: superclass, body: superclass.body ?? [], closure: superclass.closure,
        arguments: arguments, receiver: .object(instance), callingEnv: env)
      let resolved: JSObject
      if case .object(let object) = superResult { resolved = object } else { resolved = instance }
      resolved.prototype = proto
      try installInstanceFields(resolved, fields: function.instanceFields)
      return .object(resolved)
    }
    let instance = JSObject(prototype: proto)
    try installInstanceFields(instance, fields: function.instanceFields)
    if let body = function.body, let closure = function.closure, !body.isEmpty {
      let result = try runInterpreted(
        function: function, body: body, closure: closure,
        arguments: arguments, receiver: .object(instance), callingEnv: env)
      switch result {
      case .object: return result
      case .function: return result
      default: return .object(instance)
      }
    }
    return .object(instance)
  }

  private func bindConstructorParams(
    _ parameters: [JSPattern], arguments: [JSValue], scope: JSEnvironment
  ) {
    var index = 0
    for pattern in parameters {
      if case .rest(let name) = pattern {
        scope.define(name, value: .object(makeArray(Array(arguments.dropFirst(index)))))
        break
      }
      let value = index < arguments.count ? arguments[index] : .undefined
      try? bindPattern(pattern, value: value, environment: scope, kind: .parameter)
      index += 1
    }
  }

  private func installInstanceFields(
    _ instance: JSObject, fields: [(String, JSExpression?)]
  ) throws {
    for (name, initializer) in fields {
      if let initializer {
        let scope = JSEnvironment(parent: globals, kind: .function)
        let value = try evaluate(initializer, environment: scope)
        instance.set(name, value)
      } else {
        instance.set(name, .undefined)
      }
    }
  }

  private func execute(_ statement: JSStatement, environment: JSEnvironment) throws -> Flow {
    stepsUsed += 1
    if stepsUsed > stepBudget {
      throw JSError.runtime("Execution step limit exceeded")
    }
    switch statement {
    case .variable(let kind, let declarators):
      for (pattern, initializer) in declarators {
        let value: JSValue
        if let initializer {
          value = try evaluate(initializer, environment: environment)
        } else {
          if kind == .constDecl { throw JSError.syntax("Missing initializer in const") }
          value = .undefined
        }
        switch kind {
        case .varDecl:
          let scope = environment.nearestVariableScope()
          try bindPattern(pattern, value: value, environment: scope, kind: .variable)
        case .letDecl:
          try bindPattern(pattern, value: value, environment: environment, kind: .lexical)
        case .constDecl:
          try bindPattern(pattern, value: value, environment: environment, kind: .constant)
        }
      }
      return .normal(.undefined)
    case .expression(let expression):
      chainShortCircuited = false
      return .normal(try evaluate(expression, environment: environment))
    case .function(let name, let parameters, let body, let isAsync):
      let function = JSFunction(
        patterns: parameters, body: body, closure: environment, name: name ?? "",
        isAsync: isAsync)
      function.prototypeObject = JSObject(prototype: objectPrototype)
      if let name {
        if environment.hasOwnBinding(name) {
          environment.defineFunction(name, value: .function(function))
        } else {
          environment.define(name, value: .function(function))
        }
      }
      return .normal(.function(function))
    case .returnValue(let expression):
      chainShortCircuited = false
      if let expression {
        return .returnValue(try evaluate(expression, environment: environment))
      }
      return .returnValue(.undefined)
    case .block(let statements):
      let scope = JSEnvironment(parent: environment, kind: .block)
      try hoist(statements, in: scope)
      return try executeList(statements, environment: scope)
    case .conditional(let condition, let thenBranch, let elseBranch):
      chainShortCircuited = false
      if try evaluate(condition, environment: environment).truthy {
        return try execute(thenBranch, environment: environment)
      }
      if let elseBranch { return try execute(elseBranch, environment: environment) }
      return .normal(.undefined)
    case .whileLoop(let condition, let body):
      while true {
        stepsUsed += 1
        if stepsUsed > stepBudget {
          throw JSError.runtime("Execution step limit exceeded")
        }
        chainShortCircuited = false
        let whileCond = try evaluate(condition, environment: environment).truthy
        if !whileCond { break }
        let flow = try execute(body, environment: environment)
        switch flow {
        case .normal: break
        case .returnValue: return flow
        case .breakTarget(let label):
          if label == nil || labelStack.last == label { return .normal(.undefined) }
          return flow
        case .continueTarget(let label):
          if label == nil || labelStack.last == label { break }
          return flow
        }
      }
      return .normal(.undefined)
    case .doWhile(let body, let condition):
      while true {
        stepsUsed += 1
        if stepsUsed > stepBudget {
          throw JSError.runtime("Execution step limit exceeded")
        }
        let flow = try execute(body, environment: environment)
        switch flow {
        case .normal: break
        case .returnValue: return flow
        case .breakTarget(let label):
          if label == nil || labelStack.last == label { return .normal(.undefined) }
          return flow
        case .continueTarget(let label):
          if label == nil || labelStack.last == label { break }
          return flow
        }
        chainShortCircuited = false
        let doCond = try evaluate(condition, environment: environment).truthy
        if !doCond { break }
      }
      return .normal(.undefined)
    case .forLoop(let initializer, let test, let update, let body):
      let scope = JSEnvironment(parent: environment, kind: .block)
      if let initializer {
        let flow = try execute(initializer, environment: scope)
        if case .returnValue = flow { return flow }
      }
      while true {
        stepsUsed += 1
        if stepsUsed > stepBudget {
          throw JSError.runtime("Execution step limit exceeded")
        }
        if let test {
          chainShortCircuited = false
          let forCond = try evaluate(test, environment: scope).truthy
          if !forCond { break }
        }
        let flow = try execute(body, environment: scope)
        switch flow {
        case .normal: break
        case .returnValue: return flow
        case .breakTarget(let label):
          if label == nil || labelStack.last == label { return .normal(.undefined) }
          return flow
        case .continueTarget(let label):
          if label == nil || labelStack.last == label { break }
          return flow
        }
        if let update {
          chainShortCircuited = false
          _ = try evaluate(update, environment: scope)
        }
      }
      return .normal(.undefined)
    case .forIn(let binding, let target, let body):
      chainShortCircuited = false
      let value = try evaluate(target, environment: environment)
      let keys = enumerableKeys(of: value)
      return try executeForEach(
        binding: binding, values: keys.map { .string($0) }, body: body,
        environment: environment)
    case .forOf(let binding, let target, let body):
      chainShortCircuited = false
      let value = try evaluate(target, environment: environment)
      guard let items = try iterateValues(value) else {
        throw JSError.type("Value is not iterable")
      }
      return try executeForEach(
        binding: binding, values: items, body: body, environment: environment)
    case .breakStmt(let label):
      return .breakTarget(label)
    case .continueStmt(let label):
      return .continueTarget(label)
    case .throwStmt(let expression):
      chainShortCircuited = false
      throw JSError.thrown(try evaluate(expression, environment: environment))
    case .tryStmt(let body, let catchPattern, let catchBody, let finallyBody):
      return try executeTry(
        body: body, catchPattern: catchPattern, catchBody: catchBody,
        finallyBody: finallyBody, environment: environment)
    case .switchStmt(let value, let cases):
      chainShortCircuited = false
      let discriminant = try evaluate(value, environment: environment)
      return try executeSwitch(
        discriminant: discriminant, cases: cases, environment: environment)
    case .labeled(let name, let body):
      labelStack.append(name)
      defer { _ = labelStack.popLast() }
      switch body {
      case .whileLoop, .doWhile, .forLoop, .forIn, .forOf:
        let flow = try execute(body, environment: environment)
        switch flow {
        case .breakTarget(let label):
          if label == name { return .normal(.undefined) }
          return flow
        case .continueTarget(let label):
          if label == name { return .normal(.undefined) }
          return flow
        default:
          return flow
        }
      default:
        let flow = try execute(body, environment: environment)
        if case .breakTarget(let label) = flow, label == name {
          return .normal(.undefined)
        }
        return flow
      }
    case .debuggerStmt:
      return .normal(.undefined)
    case .classDecl(let name, let definition):
      let constructor = try buildClass(definition: definition, environment: environment)
      if let name {
        if environment.hasOwnBinding(name) {
          try environment.initializeLexical(name, value: .function(constructor))
        } else {
          environment.define(name, value: .function(constructor))
        }
      }
      return .normal(.undefined)
    case .importDecl(let specifiers, let path):
      try executeImport(specifiers: specifiers, path: path, environment: environment)
      return .normal(.undefined)
    case .exportDecl(let export):
      try executeExport(export: export, environment: environment)
      return .normal(.undefined)
    }
  }

  private func executeList(
    _ statements: [JSStatement], environment: JSEnvironment
  ) throws -> Flow {
    var last: JSValue = .undefined
    for statement in statements {
      let flow = try execute(statement, environment: environment)
      switch flow {
      case .normal(let value): last = value
      case .returnValue, .breakTarget, .continueTarget: return flow
      }
    }
    return .normal(last)
  }

  private func executeForEach(
    binding: JSForBinding, values: [JSValue], body: JSStatement,
    environment: JSEnvironment
  ) throws -> Flow {
    for value in values {
      stepsUsed += 1
      if stepsUsed > stepBudget {
        throw JSError.runtime("Execution step limit exceeded")
      }
      let scope = JSEnvironment(parent: environment, kind: .block)
      switch binding {
      case .declaration(let kind, let pattern):
        switch kind {
        case .varDecl:
          try bindPattern(
            pattern, value: value, environment: environment.nearestVariableScope(),
            kind: .variable)
        case .letDecl:
          try bindPattern(pattern, value: value, environment: scope, kind: .lexicalFresh)
        case .constDecl:
          try bindPattern(pattern, value: value, environment: scope, kind: .constantFresh)
        }
      case .expression(let target):
        if let pattern = patternForAssignmentTarget(target) {
          try bindPattern(pattern, value: value, environment: environment, kind: .assign)
        } else {
          let reference = try resolveReference(target, environment: environment)
          try writeReference(reference, value: value)
        }
      }
      let flow = try execute(body, environment: scope)
      switch flow {
      case .normal: break
      case .returnValue: return flow
      case .breakTarget(let label):
        if label == nil || labelStack.last == label { return .normal(.undefined) }
        return flow
      case .continueTarget(let label):
        if label == nil || labelStack.last == label { break }
        return flow
      }
    }
    return .normal(.undefined)
  }

  private func patternForAssignmentTarget(_ expression: JSExpression) -> JSPattern? {
    switch expression {
    case .identifier(let name): return .identifier(name, nil)
    case .object, .array: return nil
    default: return nil
    }
  }

  private func executeTry(
    body: [JSStatement], catchPattern: JSPattern?, catchBody: [JSStatement]?,
    finallyBody: [JSStatement]?, environment: JSEnvironment
  ) throws -> Flow {
    var pending: Flow?
    do {
      let flow = try executeList(body, environment: environment)
      switch flow {
      case .normal: break
      case .returnValue, .breakTarget, .continueTarget:
        pending = flow
      }
    } catch let error as JSError {
      switch error {
      case .thrown(let value):
        if let catchBody {
          let scope = JSEnvironment(parent: environment, kind: .block)
          if let catchPattern {
            try bindPattern(catchPattern, value: value, environment: scope, kind: .lexicalFresh)
          }
          let flow = try executeList(catchBody, environment: scope)
          switch flow {
          case .normal: break
          default: pending = flow
          }
        }
      default:
        if let catchBody {
          let scope = JSEnvironment(parent: environment, kind: .block)
          let value = errorValue(for: error)
          if let catchPattern {
            try bindPattern(catchPattern, value: value, environment: scope, kind: .lexicalFresh)
          }
          let flow = try executeList(catchBody, environment: scope)
          switch flow {
          case .normal: break
          default: pending = flow
          }
        } else {
          throw error
        }
      }
    }
    if let finallyBody {
      let flow = try executeList(finallyBody, environment: environment)
      switch flow {
      case .normal: break
      default: return flow
      }
    }
    return pending ?? .normal(.undefined)
  }

  private func executeSwitch(
    discriminant: JSValue, cases: [JSSwitchCase], environment: JSEnvironment
  ) throws -> Flow {
    var started = false
    var defaultIndex: Int?
    for (index, switchCase) in cases.enumerated() {
      if switchCase.test == nil {
        defaultIndex = index
        break
      }
    }
    var index = 0
    var matched = false
    while index < cases.count {
      let switchCase = cases[index]
      if !started {
        if let test = switchCase.test {
          chainShortCircuited = false
          if strictEqual(discriminant, try evaluate(test, environment: environment)) {
            started = true
          }
        } else if !matched {
          started = true
          matched = true
        }
      }
      if started {
        let scope = JSEnvironment(parent: environment, kind: .block)
        let flow = try executeList(switchCase.body, environment: scope)
        switch flow {
        case .normal: break
        case .returnValue, .continueTarget: return flow
        case .breakTarget(let label):
          if label == nil { return .normal(.undefined) }
          return flow
        }
      }
      index += 1
      if index >= cases.count, !started, let fallback = defaultIndex, !matched {
        matched = true
        started = true
        index = fallback
      }
    }
    _ = defaultIndex
    return .normal(.undefined)
  }

  private func hoist(_ statements: [JSStatement], in env: JSEnvironment) throws {
    for statement in statements {
      switch statement {
      case .function(let name?, _, _, _):
        let function = try makeHoistedFunction(statement: statement, environment: env)
        env.defineFunction(name, value: .function(function))
      case .variable(.varDecl, let declarators):
        let scope = env.nearestVariableScope()
        for (pattern, _) in declarators {
          for name in collectBoundNames(pattern) { scope.declareVariable(name) }
        }
      case .variable(.letDecl, let declarators):
        for (pattern, _) in declarators {
          for name in collectBoundNames(pattern) { try env.declareLexical(name, constant: false) }
        }
      case .variable(.constDecl, let declarators):
        for (pattern, _) in declarators {
          for name in collectBoundNames(pattern) { try env.declareLexical(name, constant: true) }
        }
      case .classDecl(let name?, _):
        try env.declareLexical(name, constant: true)
      case .importDecl(let specifiers, _):
        for name in specifiers.map({ importLocalName($0) }) {
          try env.declareLexical(name, constant: true)
        }
      case .exportDecl(.declaration(let inner)):
        try hoist([inner], in: env)
      default:
        break
      }
    }
  }

  private func makeHoistedFunction(
    statement: JSStatement, environment: JSEnvironment
  ) throws -> JSFunction {
    guard case .function(let name, let parameters, let body, let isAsync) = statement else {
      throw JSError.runtime("Invalid hoisted declaration")
    }
    let function = JSFunction(
      patterns: parameters, body: body, closure: environment, name: name ?? "",
      isAsync: isAsync)
    function.prototypeObject = JSObject(prototype: objectPrototype)
    return function
  }

  private func collectBoundNames(_ pattern: JSPattern) -> [String] {
    switch pattern {
    case .identifier(let name, _): return [name]
    case .object(let entries, let rest):
      var names = entries.flatMap { collectBoundNames($0.pattern) }
      if let rest { names.append(rest) }
      return names
    case .array(let elements, let rest):
      var names = elements.compactMap { $0 }.flatMap { collectBoundNames($0) }
      if let rest { names.append(contentsOf: collectBoundNames(rest)) }
      return names
    case .rest(let name): return [name]
    }
  }

  private enum BindKind {
    case variable
    case lexical
    case constant
    case lexicalFresh
    case constantFresh
    case parameter
    case assign
  }

  private func bindPattern(
    _ pattern: JSPattern, value: JSValue, environment: JSEnvironment, kind: BindKind
  ) throws {
    switch pattern {
    case .identifier(let name, let fallback):
      var resolved = value
      if case .undefined = resolved, let fallback {
        resolved = try evaluate(fallback, environment: environment)
      }
      switch kind {
      case .variable, .parameter:
        environment.define(name, value: resolved)
      case .lexical, .lexicalFresh:
        if kind == .lexicalFresh { try environment.declareLexical(name, constant: false) }
        try environment.initializeLexical(name, value: resolved)
      case .constant, .constantFresh:
        if kind == .constantFresh { try environment.declareLexical(name, constant: true) }
        try environment.initializeLexical(name, value: resolved)
      case .assign:
        try environment.checkedAssign(name, value: resolved, strict: strictDepth > 0)
      }
    case .object(let entries, let rest):
      guard case .object(let object) = value else {
        if value.isNullish {
          throw JSError.type("Cannot destructure \(value)")
        }
        throw JSError.type("Cannot destructure \(value)")
      }
      var consumed = Set<String>()
      for (key, subpattern) in entries {
        consumed.insert(key)
        try bindPattern(subpattern, value: runtimeRead(object, key), environment: environment,
          kind: kind)
      }
      if let rest {
        let remainder = JSObject(prototype: objectPrototype)
        for key in object.ownEnumerableKeys() where !consumed.contains(key) {
          remainder.set(key, object.get(key))
        }
        try bindPattern(
          .identifier(rest, nil), value: .object(remainder), environment: environment, kind: kind)
      }
    case .array(let elements, let rest):
      guard let items = try iterateValues(value) else {
        throw JSError.type("Value is not iterable")
      }
      var index = 0
      for element in elements {
        if let subpattern = element {
          let item = index < items.count ? items[index] : .undefined
          try bindPattern(subpattern, value: item, environment: environment, kind: kind)
        }
        index += 1
      }
      if let rest {
        try bindPattern(
          rest, value: .object(makeArray(Array(items.dropFirst(index)))),
          environment: environment, kind: kind)
      }
    case .rest(let name):
      try bindPattern(
        .identifier(name, nil), value: value, environment: environment, kind: kind)
    }
  }

  private func importLocalName(_ specifier: JSImportSpecifier) -> String {
    switch specifier {
    case .default(let name): return name
    case .named(_, let local): return local
    case .namespace(let name): return name
    }
  }

  func stringKey(_ value: JSValue) -> String? {
    switch value {
    case .string(let text): return text
    case .number(let number):
      if number.isNaN { return "NaN" }
      if number.isInfinite { return number > 0 ? "Infinity" : "-Infinity" }
      if number.rounded() == number && abs(number) < 1e21 { return String(Int64(number)) }
      return String(number)
    case .bigint(let text): return text
    case .bool(let flag): return flag ? "true" : "false"
    case .null: return "null"
    case .undefined: return "undefined"
    case .symbol: return nil
    case .object, .function: return nil
    }
  }

  func makeArray(_ values: [JSValue]) -> JSObject {
    let object = JSObject(prototype: arrayPrototype)
    for (index, value) in values.enumerated() { object.properties[String(index)] = value }
    object.properties["length"] = .number(Double(values.count))
    weak var weakObject = object
    object.nativeSet = { key, value in
      guard let target = weakObject else { return false }
      if key == "length" {
        let number: Double
        switch value {
        case .number(let raw): number = raw
        case .string(let text): number = Double(text) ?? .nan
        case .bool(let flag): number = flag ? 1 : 0
        case .null: number = 0
        default: return false
        }
        guard number.isFinite, number >= 0, number.rounded() == number,
          number < 4294967296
        else {
          return false
        }
        let updated = UInt32(number)
        if case .number(let current) = target.properties["length"],
          current == Double(updated)
        {
          return true
        }
        target.properties["length"] = .number(Double(updated))
        for existing in target.properties.keys.compactMap({ jsArrayIndex($0) }) {
          if existing >= updated { target.properties.removeValue(forKey: String(existing)) }
        }
        return true
      }
      if let index = jsArrayIndex(key) {
        target.properties[key] = value
        if case .number(let current) = target.properties["length"],
          Double(index) >= current
        {
          target.properties["length"] = .number(Double(index) + 1)
        }
        return true
      }
      return false
    }
    return object
  }

  func defineDataProperty(
    _ object: JSObject, _ key: String, _ value: JSValue,
    writable: Bool = true, enumerable: Bool = true, configurable: Bool = true
  ) {
    if object.properties[key] == nil && !object.isExtensible {
      return
    }
    object.properties[key] = value
    object.attributes[key] = JSPropertyAttributes(
      writable: writable, enumerable: enumerable, configurable: configurable)
  }

  func defineAccessor(
    _ object: JSObject, _ key: String, getter: JSFunction?, setter: JSFunction?,
    enumerable: Bool = true, configurable: Bool = true
  ) {
    if let getter { object.accessorGet[key] = getter }
    if let setter { object.accessorSet[key] = setter }
    object.attributes[key] = JSPropertyAttributes(
      writable: false, enumerable: enumerable, configurable: configurable)
  }

  func patternKeys(_ value: JSValue) -> [String] {
    guard case .object(let object) = value else { return [] }
    return object.ownEnumerableKeys()
  }

  func enumerableKeys(of value: JSValue) -> [String] {
    guard case .object(let object) = value else { return [] }
    var seen = Set<String>()
    var keys: [String] = []
    var current: JSObject? = object
    var visited = Set<ObjectIdentifier>()
    while let node = current {
      let id = ObjectIdentifier(node)
      if visited.contains(id) { break }
      visited.insert(id)
      for key in node.ownEnumerableKeys() where !seen.contains(key) {
        seen.insert(key)
        keys.append(key)
      }
      current = node.prototype
    }
    return keys
  }

  private func evaluate(_ expression: JSExpression, environment: JSEnvironment) throws -> JSValue {
    switch expression {
    case .literal(let literal):
      return literalValue(literal)
    case .identifier(let name):
      return try environment.checkedGet(name)
    case .thisExpr:
      return thisStack.last ?? .object(globalObject)
    case .superExpr:
      throw JSError.syntax("Unexpected super")
    case .array(let elements):
      return .object(try buildArray(elements, environment: environment))
    case .object(let members):
      return .object(try buildObject(members, environment: environment))
    case .unary(let op, let operand):
      return try evaluateUnary(op, operand, environment: environment)
    case .binary(let op, let left, let right):
      return try evaluateBinary(op, left: left, right: right, environment: environment)
    case .ternary(let condition, let thenBranch, let elseBranch):
      chainShortCircuited = false
      if try evaluate(condition, environment: environment).truthy {
        return try evaluate(thenBranch, environment: environment)
      }
      return try evaluate(elseBranch, environment: environment)
    case .sequence(let items):
      var last: JSValue = .undefined
      for item in items {
        chainShortCircuited = false
        last = try evaluate(item, environment: environment)
      }
      return last
    case .assignment(let target, let valueExpression):
      chainShortCircuited = false
      let value = try evaluate(valueExpression, environment: environment)
      let reference = try resolveReference(target, environment: environment)
      try writeReference(reference, value: value)
      return value
    case .patternAssign(let pattern, let valueExpression):
      chainShortCircuited = false
      let value = try evaluate(valueExpression, environment: environment)
      try bindPattern(pattern, value: value, environment: environment, kind: .assign)
      return value
    case .compoundAssignment(let op, let target, let valueExpression):
      return try evaluateCompoundAssignment(
        op: op, target: target, valueExpression: valueExpression, environment: environment)
    case .update(let op, let target, let isPrefix):
      return try evaluateUpdate(
        op: op, target: target, isPrefix: isPrefix, environment: environment)
    case .member(let objectExpression, let property):
      if chainShortCircuited { return .undefined }
      if case .superExpr = objectExpression {
        return runtimeRead(try superObject(), property)
      }
      let base = try evaluate(objectExpression, environment: environment)
      switch base {
      case .object(let object):
        return runtimeRead(object, property)
      case .function(let function):
        return readFunctionProperty(function, property)
      default:
        return try boxedRead(base, property)
      }
    case .optionalMember(let objectExpression, let property):
      if chainShortCircuited { return .undefined }
      if case .superExpr = objectExpression {
        return runtimeRead(try superObject(), property)
      }
      let base = try evaluate(objectExpression, environment: environment)
      if base.isNullish {
        chainShortCircuited = true
        return .undefined
      }
      switch base {
      case .object(let object):
        return runtimeRead(object, property)
      case .function(let function):
        return readFunctionProperty(function, property)
      default:
        return try boxedRead(base, property)
      }
    case .computed(let objectExpression, let keyExpression):
      if chainShortCircuited { return .undefined }
      if case .superExpr = objectExpression {
        let key = try evaluateBoundary(keyExpression, environment: environment)
        return try computedRead(base: .object(try superObject()), key: key)
      }
      let base = try evaluateBoundary(objectExpression, environment: environment)
      let key = try evaluateBoundary(keyExpression, environment: environment)
      return try computedRead(base: base, key: key)
    case .optionalComputed(let objectExpression, let keyExpression):
      if chainShortCircuited { return .undefined }
      if case .superExpr = objectExpression {
        let key = try evaluateBoundary(keyExpression, environment: environment)
        return try computedRead(base: .object(try superObject()), key: key)
      }
      let base = try evaluateBoundary(objectExpression, environment: environment)
      if base.isNullish {
        chainShortCircuited = true
        return .undefined
      }
      let key = try evaluateBoundary(keyExpression, environment: environment)
      return try computedRead(base: base, key: key)
    case .call(let calleeExpression, let argumentExpressions):
      if chainShortCircuited { return .undefined }
      return try evaluateCall(
        callee: calleeExpression, arguments: argumentExpressions, optional: false,
        environment: environment)
    case .optionalCall(let calleeExpression, let argumentExpressions):
      if chainShortCircuited { return .undefined }
      return try evaluateCall(
        callee: calleeExpression, arguments: argumentExpressions, optional: true,
        environment: environment)
    case .newExpr(let calleeExpression, let argumentExpressions):
      chainShortCircuited = false
      let callee = try evaluate(calleeExpression, environment: environment)
      var arguments: [JSValue] = []
      for argument in argumentExpressions {
        let saved = chainShortCircuited
        chainShortCircuited = false
        let value = try evaluate(argument, environment: environment)
        chainShortCircuited = saved
        if case .spread(let inner) = argument {
          _ = inner
          if let items = try iterateValues(value) {
            arguments.append(contentsOf: items)
          } else {
            throw JSError.type("Value is not iterable")
          }
        } else {
          arguments.append(value)
        }
      }
      return try construct(callee, arguments: arguments, env: environment)
    case .function(let parameters, let body, let isAsync):
      let function = JSFunction(
        patterns: parameters, body: body, closure: environment, isAsync: isAsync)
      function.prototypeObject = JSObject(prototype: objectPrototype)
      function.capturedThis = thisStack.last
      return .function(function)
    case .arrow(let parameters, let arrowBody, let isAsync):
      let function = JSFunction(
        patterns: parameters, body: arrowBody.statements, closure: environment,
        isAsync: isAsync, isArrow: true, arrowBody: arrowBody)
      function.capturedThis = thisStack.last
      return .function(function)
    case .template(let strings, let values):
      var result = strings.first ?? ""
      for (index, value) in values.enumerated() {
        result += try toString(try evaluate(value, environment: environment))
        if index + 1 < strings.count { result += strings[index + 1] }
      }
      return .string(result)
    case .taggedTemplate(let tagExpression, let strings, let values):
      chainShortCircuited = false
      let tag = try evaluate(tagExpression, environment: environment)
      var cooked: [JSValue] = []
      var raw: [JSValue] = []
      for text in strings {
        cooked.append(.string(text))
        raw.append(.string(text))
      }
      let templateObject = JSObject(prototype: objectPrototype)
      templateObject.set("raw", .object(makeArray(raw)))
      for (index, value) in cooked.enumerated() {
        templateObject.set(String(index), value)
      }
      templateObject.set("length", .number(Double(cooked.count)))
      var arguments: [JSValue] = [.object(templateObject)]
      for value in values {
        arguments.append(try evaluate(value, environment: environment))
      }
      return try callValue(tag, thisValue: .undefined, arguments: arguments, env: environment)
    case .classExpr(let definition):
      return .function(try buildClass(definition: definition, environment: environment))
    case .awaitExpr(let inner):
      guard asyncDepth > 0 else {
        throw JSError.syntax("await is only valid in async functions")
      }
      chainShortCircuited = false
      return try awaitValue(try evaluate(inner, environment: environment))
    case .yieldExpr:
      throw JSError.syntax("Generators are not yet supported")
    case .spread(let inner):
      return try evaluate(inner, environment: environment)
    case .dynamicImport(let pathExpression):
      chainShortCircuited = false
      let path = try evaluate(pathExpression, environment: environment)
      return importModule(named: try toString(path))
    }
  }

  private func evaluateBoundary(
    _ expression: JSExpression, environment: JSEnvironment
  ) throws -> JSValue {
    let saved = chainShortCircuited
    chainShortCircuited = false
    defer { chainShortCircuited = saved }
    return try evaluate(expression, environment: environment)
  }

  private func computedRead(base: JSValue, key: JSValue) throws -> JSValue {
    switch base {
    case .object(let object):
      if case .symbol(let id) = key {
        return object.symbolProperties[id] ?? .undefined
      }
      guard let name = stringKey(key) ?? (try? toString(key)) else { return .undefined }
      return runtimeRead(object, name)
    case .function(let function):
      if case .symbol = key { return .undefined }
      guard let name = stringKey(key) ?? (try? toString(key)) else { return .undefined }
      return readFunctionProperty(function, name)
    default:
      if case .symbol = key { return .undefined }
      guard let name = stringKey(key) ?? (try? toString(key)) else { return .undefined }
      return try boxedRead(base, name)
    }
  }

  private func buildArray(
    _ elements: [JSArrayElement], environment: JSEnvironment
  ) throws -> JSObject {
    var values: [JSValue] = []
    var holes = Set<Int>()
    for element in elements {
      switch element {
      case .value(let expression):
        chainShortCircuited = false
        values.append(try evaluate(expression, environment: environment))
      case .hole:
        holes.insert(values.count)
        values.append(.undefined)
      case .spread(let expression):
        chainShortCircuited = false
        let value = try evaluate(expression, environment: environment)
        guard let items = try iterateValues(value) else {
          throw JSError.type("Value is not iterable")
        }
        values.append(contentsOf: items)
      }
    }
    let object = makeArray(values)
    for hole in holes { object.properties.removeValue(forKey: String(hole)) }
    return object
  }

  private func buildObject(
    _ members: [JSObjectMember], environment: JSEnvironment
  ) throws -> JSObject {
    let object = JSObject(prototype: objectPrototype)
    for member in members {
      switch member {
      case .property("__proto__", let expression):
        chainShortCircuited = false
        let value = try evaluate(expression, environment: environment)
        if case .object(let proto) = value {
          object.prototype = proto
        } else if !value.isNullish {
          throw JSError.type("Prototype must be an object or null")
        } else {
          object.prototype = nil
        }
      case .property(let key, let expression):
        chainShortCircuited = false
        object.set(key, try evaluate(expression, environment: environment))
      case .shorthand(let name):
        object.set(name, try environment.checkedGet(name))
      case .computed(let keyExpression, let valueExpression):
        chainShortCircuited = false
        let key = try evaluate(keyExpression, environment: environment)
        let value = try evaluate(valueExpression, environment: environment)
        if case .symbol(let id) = key {
          object.symbolProperties[id] = value
        } else {
          object.set(try toString(key), value)
        }
      case .spread(let expression):
        chainShortCircuited = false
        let value = try evaluate(expression, environment: environment)
        if case .object(let source) = value {
          for key in source.ownEnumerableKeys() { object.set(key, source.get(key)) }
        } else if !value.isNullish {
          throw JSError.type("Cannot spread \(value)")
        }
      case .method(let name, let parameters, let body, let isAsync):
        let function = JSFunction(
          patterns: parameters, body: body, closure: environment, name: name,
          isAsync: isAsync)
        function.isMethod = true
        function.homeObject = object
        function.capturedThis = thisStack.last
        object.set(name, .function(function))
      case .getter(let name, let body):
        let function = JSFunction(
          patterns: [], body: body, closure: environment, name: "get \(name)")
        function.isMethod = true
        function.homeObject = object
        function.capturedThis = thisStack.last
        defineAccessor(object, name, getter: function, setter: object.accessorSet[name])
      case .setter(let name, let parameter, let body):
        let function = JSFunction(
          patterns: [.identifier(parameter, nil)], body: body, closure: environment,
          name: "set \(name)")
        function.isMethod = true
        function.homeObject = object
        function.capturedThis = thisStack.last
        defineAccessor(object, name, getter: object.accessorGet[name], setter: function)
      }
    }
    return object
  }

  private func evaluateUnary(
    _ op: String, _ operand: JSExpression, environment: JSEnvironment
  ) throws -> JSValue {
    if op == "delete" {
      return try evaluateDelete(operand, environment: environment)
    }
    chainShortCircuited = false
    let value = try evaluate(operand, environment: environment)
    switch op {
    case "!": return .bool(!value.truthy)
    case "-":
      if case .bigint(let text) = value { return .bigint(JSBigInt.negate(text)) }
      return .number(try toNumber(value))
    case "+": return .number(try toNumber(value))
    case "~":
      if case .bigint(let text) = value {
        return .bigint(JSBigInt.subtract("-1", text))
      }
      return .number(Double(~toInt32(try toNumber(value))))
    case "typeof": return .string(typeName(of: value))
    case "void": return .undefined
    default: throw JSError.runtime("Unknown unary operator \(op)")
    }
  }

  private func evaluateDelete(
    _ operand: JSExpression, environment: JSEnvironment
  ) throws -> JSValue {
    switch operand {
    case .member(let base, let property):
      let target = try evaluate(base, environment: environment)
      if case .object(let object) = target { return .bool(object.deleteOwn(property)) }
      return .bool(true)
    case .computed(let base, let key):
      let target = try evaluate(base, environment: environment)
      let name = try evaluate(key, environment: environment)
      if case .object(let object) = target, let key = stringKey(name) {
        return .bool(object.deleteOwn(key))
      }
      return .bool(true)
    case .identifier:
      if strictDepth > 0 { throw JSError.syntax("Delete of an unqualified identifier") }
      return .bool(false)
    default:
      _ = try evaluate(operand, environment: environment)
      return .bool(true)
    }
  }

  private func evaluateBinary(
    _ op: String, left: JSExpression, right: JSExpression, environment: JSEnvironment
  ) throws -> JSValue {
    if op == "&&" {
      chainShortCircuited = false
      let lhs = try evaluate(left, environment: environment)
      return lhs.truthy ? try evaluate(right, environment: environment) : lhs
    }
    if op == "||" {
      chainShortCircuited = false
      let lhs = try evaluate(left, environment: environment)
      return lhs.truthy ? lhs : try evaluate(right, environment: environment)
    }
    if op == "??" {
      chainShortCircuited = false
      let lhs = try evaluate(left, environment: environment)
      return lhs.isNullish ? try evaluate(right, environment: environment) : lhs
    }
    chainShortCircuited = false
    let lhs = try evaluate(left, environment: environment)
    let rhs = try evaluate(right, environment: environment)
    return try applyBinary(op, lhs: lhs, rhs: rhs)
  }

  func applyBinary(_ op: String, lhs: JSValue, rhs: JSValue) throws -> JSValue {
    switch op {
    case "+":
      if case .bigint = lhs, case .bigint = rhs {
        if case .bigint(let a) = lhs, case .bigint(let b) = rhs {
          return .bigint(JSBigInt.add(a, b))
        }
      }
      if case .bigint = lhs { throw JSError.type("Cannot mix BigInt with other types") }
      if case .bigint = rhs { throw JSError.type("Cannot mix BigInt with other types") }
      let leftPrimitive = try toPrimitive(lhs)
      let rightPrimitive = try toPrimitive(rhs)
      if case .string = leftPrimitive {
        return .string(try toString(leftPrimitive) + toString(rightPrimitive))
      }
      if case .string = rightPrimitive {
        return .string(try toString(leftPrimitive) + toString(rightPrimitive))
      }
      return .number(try toNumber(leftPrimitive) + toNumber(rightPrimitive))
    case "-":
      if case .bigint(let a) = lhs, case .bigint(let b) = rhs {
        return .bigint(JSBigInt.subtract(a, b))
      }
      if case .bigint = lhs { throw JSError.type("Cannot mix BigInt with other types") }
      if case .bigint = rhs { throw JSError.type("Cannot mix BigInt with other types") }
      return .number(try toNumber(lhs) - toNumber(rhs))
    case "*":
      if case .bigint(let a) = lhs, case .bigint(let b) = rhs {
        return .bigint(JSBigInt.multiply(a, b))
      }
      if case .bigint = lhs { throw JSError.type("Cannot mix BigInt with other types") }
      if case .bigint = rhs { throw JSError.type("Cannot mix BigInt with other types") }
      return .number(try toNumber(lhs) * toNumber(rhs))
    case "/":
      if case .bigint(let a) = lhs, case .bigint(let b) = rhs {
        return .bigint(try JSBigInt.divide(a, b))
      }
      if case .bigint = lhs { throw JSError.type("Cannot mix BigInt with other types") }
      if case .bigint = rhs { throw JSError.type("Cannot mix BigInt with other types") }
      return .number(try toNumber(lhs) / toNumber(rhs))
    case "%":
      if case .bigint(let a) = lhs, case .bigint(let b) = rhs {
        return .bigint(try JSBigInt.remainder(a, b))
      }
      if case .bigint = lhs { throw JSError.type("Cannot mix BigInt with other types") }
      if case .bigint = rhs { throw JSError.type("Cannot mix BigInt with other types") }
      return .number(try toNumber(lhs).truncatingRemainder(dividingBy: toNumber(rhs)))
    case "**":
      if case .bigint(let a) = lhs, case .bigint(let b) = rhs {
        return .bigint(try JSBigInt.power(a, b))
      }
      if case .bigint = lhs { throw JSError.type("Cannot mix BigInt with other types") }
      if case .bigint = rhs { throw JSError.type("Cannot mix BigInt with other types") }
      return .number(pow(try toNumber(lhs), try toNumber(rhs)))
    case "<": return try relational(lhs, rhs, less: true, swapped: false)
    case ">": return try relational(rhs, lhs, less: true, swapped: false)
    case "<=": return try relational(rhs, lhs, less: false, swapped: false)
    case ">=": return try relational(lhs, rhs, less: false, swapped: false)
    case "==": return .bool(try looseEqual(lhs, rhs))
    case "!=": return .bool(!(try looseEqual(lhs, rhs)))
    case "===", "!==":
      if op == "===" { return .bool(strictEqual(lhs, rhs)) }
      return .bool(!strictEqual(lhs, rhs))
    case "instanceof": return .bool(try instanceOf(lhs, rhs))
    case "in":
      guard case .object(let object) = rhs else {
        throw JSError.type("Right-hand side of in must be an object")
      }
      if case .symbol(let id) = lhs { return .bool(object.symbolProperties[id] != nil) }
      return .bool(hasProperty(object, try toString(lhs)))
    case "&", "|", "^", "<<", ">>", ">>>":
      if case .bigint(let a) = lhs, case .bigint(let b) = rhs {
        switch op {
        case "&": return .bigint(JSBigInt.bitwise(a, b, "and"))
        case "|": return .bigint(JSBigInt.bitwise(a, b, "or"))
        case "^": return .bigint(JSBigInt.bitwise(a, b, "xor"))
        case "<<": return .bigint(try JSBigInt.shift(a, b, right: false))
        case ">>": return .bigint(try JSBigInt.shift(a, b, right: true))
        default: throw JSError.type(">>> cannot be applied to BigInt")
        }
      }
      if case .bigint = lhs { throw JSError.type("Cannot mix BigInt with other types") }
      if case .bigint = rhs { throw JSError.type("Cannot mix BigInt with other types") }
      let a = toInt32(try toNumber(lhs))
      let b = toInt32(try toNumber(rhs))
      switch op {
      case "&": return .number(Double(a & b))
      case "|": return .number(Double(a | b))
      case "^": return .number(Double(a ^ b))
      case "<<": return .number(Double(a &<< (b & 31)))
      case ">>": return .number(Double(a &>> (b & 31)))
      default:
        let unsigned = toUint32(try toNumber(lhs))
        return .number(Double(unsigned >> (toUint32(try toNumber(rhs)) & 31)))
      }
    default: throw JSError.runtime("Unknown binary operator \(op)")
    }
  }

  private func relational(
    _ lhs: JSValue, _ rhs: JSValue, less: Bool, swapped: Bool
  ) throws -> JSValue {
    let leftPrimitive = try toPrimitive(lhs, hint: .number)
    let rightPrimitive = try toPrimitive(rhs, hint: .number)
    if case .string(let a) = leftPrimitive, case .string(let b) = rightPrimitive {
      if less { return .bool(a < b) }
      return .bool(!(a < b))
    }
    if case .bigint(let a) = leftPrimitive, case .bigint(let b) = rightPrimitive {
      let order = JSBigInt.compare(a, b)
      if less { return .bool(order < 0) }
      return .bool(order >= 0)
    }
    let a = try toNumber(leftPrimitive)
    let b = try toNumber(rightPrimitive)
    if a.isNaN || b.isNaN { return .bool(false) }
    if less { return .bool(a < b) }
    _ = swapped
    return .bool(!(a < b))
  }

  private func evaluateCall(
    callee: JSExpression, arguments: [JSExpression], optional: Bool,
    environment: JSEnvironment
  ) throws -> JSValue {
    if case .member(let base, let property) = callee {
      let saved = chainShortCircuited
      chainShortCircuited = false
      let receiver: JSValue
      if case .superExpr = base {
        receiver = .object(try superObject())
      } else {
        receiver = try evaluate(base, environment: environment)
      }
      chainShortCircuited = saved
      if optional && receiver.isNullish {
        chainShortCircuited = true
        return .undefined
      }
      let method: JSValue
      switch receiver {
      case .object(let object): method = runtimeRead(object, property)
      case .function(let function):
        method = readFunctionProperty(function, property)
      default: method = try boxedRead(receiver, property)
      }
      if chainShortCircuited { return .undefined }
      let args = try evaluateArguments(arguments, environment: environment)
      return try callValue(method, thisValue: receiver, arguments: args, env: environment)
    }
    if case .computed(let base, let key) = callee {
      let saved = chainShortCircuited
      chainShortCircuited = false
      let receiver: JSValue
      if case .superExpr = base {
        receiver = .object(try superObject())
      } else {
        receiver = try evaluate(base, environment: environment)
      }
      let keyValue = try evaluateBoundary(key, environment: environment)
      chainShortCircuited = saved
      if optional && receiver.isNullish {
        chainShortCircuited = true
        return .undefined
      }
      let method = try computedRead(base: receiver, key: keyValue)
      if chainShortCircuited { return .undefined }
      let args = try evaluateArguments(arguments, environment: environment)
      return try callValue(method, thisValue: receiver, arguments: args, env: environment)
    }
    if case .superExpr = callee {
      let args = try evaluateArguments(arguments, environment: environment)
      return try superCall(arguments: args, environment: environment)
    }
    if case .optionalMember(let base, let property) = callee {
      let saved = chainShortCircuited
      chainShortCircuited = false
      let receiver = try evaluate(base, environment: environment)
      chainShortCircuited = saved
      if receiver.isNullish {
        chainShortCircuited = true
        return .undefined
      }
      let method: JSValue
      switch receiver {
      case .object(let object): method = runtimeRead(object, property)
      default: method = try boxedRead(receiver, property)
      }
      let args = try evaluateArguments(arguments, environment: environment)
      return try callValue(method, thisValue: receiver, arguments: args, env: environment)
    }
    chainShortCircuited = false
    let target = try evaluate(callee, environment: environment)
    if optional && target.isNullish {
      chainShortCircuited = true
      return .undefined
    }
    let args = try evaluateArguments(arguments, environment: environment)
    return try callValue(target, thisValue: .undefined, arguments: args, env: environment)
  }

  private func evaluateArguments(
    _ expressions: [JSExpression], environment: JSEnvironment
  ) throws -> [JSValue] {
    var arguments: [JSValue] = []
    for expression in expressions {
      let saved = chainShortCircuited
      chainShortCircuited = false
      if case .spread(let inner) = expression {
        let value = try evaluate(inner, environment: environment)
        chainShortCircuited = saved
        guard let items = try iterateValues(value) else {
          throw JSError.type("Value is not iterable")
        }
        arguments.append(contentsOf: items)
      } else {
        let value = try evaluate(expression, environment: environment)
        chainShortCircuited = saved
        arguments.append(value)
      }
    }
    return arguments
  }

  private func superCall(arguments: [JSValue], environment: JSEnvironment) throws -> JSValue {
    guard let frame = ctorFieldStack.last else {
      throw JSError.syntax("super() call outside a derived constructor")
    }
    guard let superclass = superConstructorStack.last ?? nil else {
      throw JSError.syntax("super() call outside a derived constructor")
    }
    guard case .function(let superFunction) = JSValue.function(superclass) else {
      throw JSError.type("Super constructor is not callable")
    }
    let derivedProto: JSObject? = superStack.last ?? nil
    let instance = JSObject()
    let result: JSValue
    if superFunction.isClass {
      result = try constructClass(superFunction, arguments: arguments, env: environment)
    } else if superFunction.body != nil {
      result = try runInterpreted(
        function: superFunction, body: superFunction.body ?? [],
        closure: superFunction.closure, arguments: arguments,
        receiver: .object(instance), callingEnv: environment)
    } else if let native = superFunction.native {
      _ = try native(arguments)
      result = .object(instance)
    } else {
      throw JSError.type("Super constructor is not callable")
    }
    let resolved: JSObject
    if case .object(let object) = result { resolved = object } else { resolved = instance }
    if let derivedProto { resolved.prototype = derivedProto }
    try installInstanceFields(resolved, fields: frame.fields)
    frame.instance = resolved
    if !thisStack.isEmpty { thisStack[thisStack.count - 1] = .object(resolved) }
    return .object(resolved)
  }

  private func resolveReference(
    _ target: JSExpression, environment: JSEnvironment
  ) throws -> JSReference {
    switch target {
    case .identifier(let name):
      var scope: JSEnvironment? = environment
      while let current = scope {
        if current.hasOwnBinding(name) { return .variable(current, name) }
        scope = current.parent
      }
      if strictDepth > 0 { throw JSError.reference("\(name) is not defined") }
      return .variable(globals, name)
    case .member(let base, let property):
      if case .superExpr = base {
        guard let proto = superStack.last ?? nil else {
          throw JSError.syntax("Unexpected super")
        }
        return .property(.object(proto), property)
      }
      let receiver = try evaluate(base, environment: environment)
      return .property(receiver, property)
    case .computed(let base, let key):
      if case .superExpr = base {
        guard let proto = superStack.last ?? nil else {
          throw JSError.syntax("Unexpected super")
        }
        let keyValue = try evaluateBoundary(key, environment: environment)
        if case .symbol(let id) = keyValue { return .symbolProperty(.object(proto), id) }
        return .property(.object(proto), try toString(keyValue))
      }
      let receiver = try evaluate(base, environment: environment)
      let keyValue = try evaluateBoundary(key, environment: environment)
      if case .symbol(let id) = keyValue { return .symbolProperty(receiver, id) }
      return .property(receiver, try toString(keyValue))
    default:
      throw JSError.syntax("Invalid assignment target")
    }
  }

  private func readReference(_ reference: JSReference) throws -> JSValue {
    switch reference {
    case .variable(let scope, let name):
      return try scope.checkedGet(name)
    case .property(let base, let key):
      if case .object(let object) = base { return runtimeRead(object, key) }
      if case .function(let function) = base {
        return readFunctionProperty(function, key)
      }
      return try boxedRead(base, key)
    case .symbolProperty(let base, let id):
      if case .object(let object) = base {
        return object.symbolProperties[id] ?? .undefined
      }
      return .undefined
    }
  }

  private func writeReference(_ reference: JSReference, value: JSValue) throws {
    switch reference {
    case .variable(let scope, let name):
      if scope.hasOwnBinding(name) {
        try scope.checkedAssign(name, value: value, strict: strictDepth > 0)
      } else {
        scope.define(name, value: value)
      }
    case .property(let base, let key):
      try runtimeWrite(base: base, key: key, value: value)
    case .symbolProperty(let base, let id):
      if case .object(let object) = base {
        object.symbolProperties[id] = value
      } else {
        throw JSError.type("Cannot set property on \(base)")
      }
    }
  }

  func readFunctionProperty(_ function: JSFunction, _ key: String) -> JSValue {
    if key == "length", !function.staticProperties.hasOwn("length") {
      return .number(Double(function.parameters.count))
    }
    if key == "prototype" {
      if function.isArrow { return .undefined }
      if let proto = function.prototypeObject { return .object(proto) }
      return .undefined
    }
    if function.staticProperties.hasOwn(key) {
      return function.staticProperties.get(key)
    }
    return runtimeRead(functionPrototype, key)
  }

  func runtimeRead(_ object: JSObject, _ key: String) -> JSValue {
    if let native = object.nativeGet?(key) { return native }
    if let getter = object.accessorGet[key] {
      do {
        return try callValue(
          .function(getter), thisValue: .object(object), arguments: [], env: nil)
      } catch {
        return .undefined
      }
    }
    var current: JSObject? = object
    var visited = Set<ObjectIdentifier>()
    while let node = current {
      let id = ObjectIdentifier(node)
      if visited.contains(id) { break }
      visited.insert(id)
      if let value = node.properties[key] { return value }
      if let getter = node.accessorGet[key] {
        do {
          return try callValue(
            .function(getter), thisValue: .object(object), arguments: [], env: nil)
        } catch {
          return .undefined
        }
      }
      current = node.prototype
    }
    return .undefined
  }

  func runtimeGet(_ base: JSValue, _ key: String) -> JSValue {
    if case .object(let object) = base { return runtimeRead(object, key) }
    if case .function(let function) = base {
      return readFunctionProperty(function, key)
    }
    return (try? boxedRead(base, key)) ?? .undefined
  }

  func runtimeWrite(base: JSValue, key: String, value: JSValue) throws {
    if case .object(let object) = base {
      if object.nativeSet?(key, value) == true { return }
      if let setter = object.accessorSet[key] {
        _ = try callValue(
          .function(setter), thisValue: base, arguments: [value], env: nil)
        return
      }
      var current: JSObject? = object.prototype
      var visited = Set<ObjectIdentifier>()
      while let node = current {
        let id = ObjectIdentifier(node)
        if visited.contains(id) { break }
        visited.insert(id)
        if let setter = node.accessorSet[key] {
          _ = try callValue(
            .function(setter), thisValue: base, arguments: [value], env: nil)
          return
        }
        current = node.prototype
      }
      if object.attributes[key]?.writable == false {
        throw JSError.type("Cannot assign to read-only property \(key)")
      }
      if object.properties[key] == nil && !object.isExtensible {
        throw JSError.type("Cannot add property \(key)")
      }
      object.properties[key] = value
      return
    }
    if case .function(let function) = base {
      function.staticProperties.set(key, value)
      return
    }
    throw JSError.type("Cannot set property \(key) on \(base)")
  }

  private func boxedRead(_ base: JSValue, _ key: String) throws -> JSValue {
    switch base {
    case .string(let text):
      if key == "length" { return .number(Double(text.count)) }
      let wrapper = JSObject(prototype: stringPrototype)
      wrapper.set("length", .number(Double(text.count)))
      wrapper.set("value", .string(text))
      let found = runtimeRead(wrapper, key)
      if case .undefined = found {
        if let index = Int(key), index >= 0, index < text.count {
          let character = text[text.index(text.startIndex, offsetBy: index)]
          return .string(String(character))
        }
      }
      return found
    case .number(let number):
      if key == "length" { return .undefined }
      let wrapper = JSObject(prototype: numberPrototype)
      wrapper.set("value", .number(number))
      return runtimeRead(wrapper, key)
    case .bool(let flag):
      let wrapper = JSObject(prototype: booleanPrototype)
      wrapper.set("value", .bool(flag))
      return runtimeRead(wrapper, key)
    case .bigint(let text):
      let wrapper = JSObject(prototype: objectPrototype)
      wrapper.set("value", .bigint(text))
      return runtimeRead(wrapper, key)
    case .symbol(let id):
      if key == "description" {
        if let text = symbolDescriptions[id] { return .string(text) }
        return .undefined
      }
      return runtimeRead(symbolPrototype, key)
    case .null, .undefined:
      throw JSError.type("Cannot read property \(key) of \(base)")
    case .object, .function:
      throw JSError.type("Cannot read property \(key)")
    }
  }

  private func evaluateCompoundAssignment(
    op: String, target: JSExpression, valueExpression: JSExpression,
    environment: JSEnvironment
  ) throws -> JSValue {
    if op == "&&=" || op == "||=" || op == "??=" {
      let reference = try resolveReference(target, environment: environment)
      let current = try readReference(reference)
      let shouldAssign: Bool
      switch op {
      case "&&=": shouldAssign = current.truthy
      case "||=": shouldAssign = !current.truthy
      default: shouldAssign = current.isNullish
      }
      if !shouldAssign { return current }
      chainShortCircuited = false
      let value = try evaluate(valueExpression, environment: environment)
      try writeReference(reference, value: value)
      return value
    }
    let reference = try resolveReference(target, environment: environment)
    let current = try readReference(reference)
    chainShortCircuited = false
    let value = try evaluate(valueExpression, environment: environment)
    let baseOp = String(op.dropLast())
    let result = try applyBinary(baseOp, lhs: current, rhs: value)
    try writeReference(reference, value: result)
    return result
  }

  private func evaluateUpdate(
    op: String, target: JSExpression, isPrefix: Bool, environment: JSEnvironment
  ) throws -> JSValue {
    let reference = try resolveReference(target, environment: environment)
    let current = try readReference(reference)
    let number: Double
    let big: String?
    if case .bigint(let text) = current {
      big = text
      number = 0
    } else {
      big = nil
      number = try toNumber(current)
    }
    let updated: JSValue
    if let big {
      updated = .bigint(op == "++" ? JSBigInt.add(big, "1") : JSBigInt.subtract(big, "1"))
    } else {
      updated = .number(op == "++" ? number + 1 : number - 1)
    }
    try writeReference(reference, value: updated)
    return isPrefix ? updated : current
  }

  enum PrimitiveHint {
    case `default`
    case number
    case string
  }

  func toObject(_ value: JSValue) throws -> JSValue {
    switch value {
    case .object, .function:
      return value
    case .string(let text):
      let wrapper = JSObject(prototype: stringPrototype)
      wrapper.set("length", .number(Double(text.count)))
      wrapper.set("value", .string(text))
      return .object(wrapper)
    case .number(let number):
      let wrapper = JSObject(prototype: numberPrototype)
      wrapper.set("value", .number(number))
      return .object(wrapper)
    case .bool(let flag):
      let wrapper = JSObject(prototype: booleanPrototype)
      wrapper.set("value", .bool(flag))
      return .object(wrapper)
    case .bigint(let text):
      let wrapper = JSObject(prototype: objectPrototype)
      wrapper.set("value", .bigint(text))
      return .object(wrapper)
    case .symbol(let id):
      let wrapper = JSObject(prototype: symbolPrototype)
      wrapper.set("value", .symbol(id))
      return .object(wrapper)
    case .null, .undefined:
      throw JSError.type("Cannot convert \(value) to object")
    }
  }

  func toPrimitive(_ value: JSValue, hint: PrimitiveHint = .default) throws -> JSValue {
    switch value {
    case .object(let object):
      let order: [String]
      if hint == .string { order = ["toString", "valueOf"] }
      else { order = ["valueOf", "toString"] }
      for name in order {
        let method = runtimeRead(object, name)
        if case .function = method {
          let result = try callValue(method, thisValue: value, arguments: [], env: nil)
          switch result {
          case .object, .function: break
          default: return result
          }
        }
      }
      throw JSError.type("Cannot convert object to primitive")
    default:
      return value
    }
  }

  func toNumber(_ value: JSValue) throws -> Double {
    switch value {
    case .number(let number): return number
    case .bigint: throw JSError.type("Cannot convert BigInt to number")
    case .string(let text): return jsParseNumber(text)
    case .bool(let flag): return flag ? 1 : 0
    case .null: return 0
    case .undefined: return .nan
    case .symbol: throw JSError.type("Cannot convert Symbol to number")
    case .object, .function: return try toNumber(try toPrimitive(value, hint: .number))
    }
  }

  func toString(_ value: JSValue) throws -> String {
    switch value {
    case .string(let text): return text
    case .number(let number):
      if number.isNaN { return "NaN" }
      if number.isInfinite { return number > 0 ? "Infinity" : "-Infinity" }
      if number == 0 { return "0" }
      if number.rounded() == number && abs(number) < 1e21 { return String(Int64(number)) }
      return String(number)
    case .bigint(let text): return text
    case .bool(let flag): return flag ? "true" : "false"
    case .null: return "null"
    case .undefined: return "undefined"
    case .symbol: throw JSError.type("Cannot convert Symbol to string")
    case .object(let object):
      let toStringMethod = runtimeRead(object, "toString")
      if case .function = toStringMethod {
        let custom = try callValue(
          toStringMethod, thisValue: value, arguments: [], env: nil)
        switch custom {
        case .object, .function: break
        default: return try toString(custom)
        }
      }
      return defaultObjectString(object)
    case .function(let function):
      return function.description
    }
  }

  func defaultObjectString(_ object: JSObject) -> String {
    if object.promiseState != nil { return "[object Promise]" }
    if object.isArrayBuffer { return "[object ArrayBuffer]" }
    return "[object Object]"
  }

  func jsParseNumber(_ text: String) -> Double {
    let work = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if work.isEmpty { return 0 }
    let lower = work.lowercased()
    if lower.hasPrefix("0x") {
      return Double(UInt64(work.dropFirst(2), radix: 16) ?? 0)
    }
    if lower.hasPrefix("0b") {
      return Double(UInt64(work.dropFirst(2), radix: 2) ?? 0)
    }
    if lower.hasPrefix("0o") {
      return Double(UInt64(work.dropFirst(2), radix: 8) ?? 0)
    }
    if lower == "infinity" || lower == "+infinity" { return .infinity }
    if lower == "-infinity" { return -.infinity }
    return Double(work) ?? .nan
  }

  func toInt32(_ number: Double) -> Int32 {
    if number.isNaN || number.isInfinite { return 0 }
    let truncated = number.truncatingRemainder(dividingBy: 4294967296)
    let adjusted = truncated < 0 ? truncated + 4294967296 : truncated
    if adjusted >= 2147483648 { return Int32(bitPattern: UInt32(adjusted)) }
    return Int32(adjusted)
  }

  func toUint32(_ number: Double) -> UInt32 {
    if number.isNaN || number.isInfinite { return 0 }
    let truncated = number.truncatingRemainder(dividingBy: 4294967296)
    let adjusted = truncated < 0 ? truncated + 4294967296 : truncated
    return UInt32(adjusted)
  }

  func typeName(of value: JSValue) -> String {
    switch value {
    case .undefined: return "undefined"
    case .null: return "object"
    case .bool: return "boolean"
    case .number: return "number"
    case .bigint: return "bigint"
    case .string: return "string"
    case .symbol: return "symbol"
    case .function: return "function"
    case .object: return "object"
    }
  }

  func strictEqual(_ lhs: JSValue, _ rhs: JSValue) -> Bool {
    switch (lhs, rhs) {
    case (.number(let a), .number(let b)): return a == b
    case (.bigint(let a), .bigint(let b)): return a == b
    case (.string(let a), .string(let b)): return a == b
    case (.bool(let a), .bool(let b)): return a == b
    case (.symbol(let a), .symbol(let b)): return a == b
    case (.null, .null), (.undefined, .undefined): return true
    case (.object(let a), .object(let b)): return a === b
    case (.function(let a), .function(let b)): return a === b
    default: return false
    }
  }

  func looseEqual(_ lhs: JSValue, _ rhs: JSValue) throws -> Bool {
    if strictEqual(lhs, rhs) { return true }
    if lhs.isNullish && rhs.isNullish { return true }
    if case .number = lhs, case .string = rhs { return try toNumber(lhs) == toNumber(rhs) }
    if case .string = lhs, case .number = rhs { return try toNumber(lhs) == toNumber(rhs) }
    if case .bigint(let a) = lhs, case .bigint(let b) = rhs { return a == b }
    if case .bigint = lhs, case .string = rhs {
      return (try? JSBigInt.parse(rhs)) == (try? JSBigInt.parse(lhs))
    }
    if case .string = lhs, case .bigint = rhs {
      return (try? JSBigInt.parse(lhs)) == (try? JSBigInt.parse(rhs))
    }
    if case .bigint(let text) = lhs, case .number(let number) = rhs {
      if number.isNaN || number.isInfinite { return false }
      if number.rounded() != number { return false }
      return text == JSBigInt.normalize(String(Int64(number)))
    }
    if case .number(let number) = lhs, case .bigint(let text) = rhs {
      if number.isNaN || number.isInfinite { return false }
      if number.rounded() != number { return false }
      return JSBigInt.normalize(String(Int64(number))) == text
    }
    if case .bool = lhs { return try looseEqual(.number(try toNumber(lhs)), rhs) }
    if case .bool = rhs { return try looseEqual(lhs, .number(try toNumber(rhs))) }
    if case .object = lhs, !(rhs.isNullish) {
      if case .object = rhs { return false }
      return try looseEqual(try toPrimitive(lhs, hint: .default), rhs)
    }
    if case .object = rhs, !(lhs.isNullish) {
      if case .object = lhs { return false }
      return try looseEqual(lhs, try toPrimitive(rhs, hint: .default))
    }
    return false
  }

  func instanceOf(_ value: JSValue, _ constructor: JSValue) throws -> Bool {
    guard case .function(let function) = constructor else {
      throw JSError.type("Right-hand side of instanceof is not callable")
    }
    let hasInstance = function.staticProperties.get("prototype")
    guard case .object(let prototype) = function.prototypeObject.map({ JSValue.object($0) })
      ?? hasInstanceObject(function) else {
      throw JSError.type("Function has no prototype for instanceof")
    }
    var current: JSValue? = value
    var depth = 0
    while let node = current, depth < 128 {
      depth += 1
      switch node {
      case .object(let object):
        if let proto = object.prototype, proto === prototype { return true }
        if let proto = object.prototype {
          current = .object(proto)
        } else {
          current = nil
        }
      case .function(let function):
        if let proto = function.prototypeObject, proto === prototype { return true }
        current = nil
      default:
        return false
      }
    }
    return false
  }

  private func hasInstanceObject(_ function: JSFunction) -> JSValue? {
    if let proto = function.prototypeObject { return .object(proto) }
    return nil
  }

  func hasProperty(_ object: JSObject, _ key: String) -> Bool {
    var current: JSObject? = object
    var visited = Set<ObjectIdentifier>()
    while let node = current {
      let id = ObjectIdentifier(node)
      if visited.contains(id) { break }
      visited.insert(id)
      if node.hasOwn(key) { return true }
      current = node.prototype
    }
    return false
  }

  private func literalValue(_ literal: JSLiteral) -> JSValue {
    switch literal {
    case .number(let value): return .number(value)
    case .bigint(let text): return .bigint(JSBigInt.normalize(text))
    case .string(let value): return .string(value)
    case .bool(let value): return .bool(value)
    case .null: return .null
    case .undefined: return .undefined
    case .regex(let pattern, let flags):
      if let constructor = regexpConstructor {
        let result = try? construct(
          .function(constructor), arguments: [.string(pattern), .string(flags)])
        return result ?? .undefined
      }
      return .undefined
    }
  }

  private func awaitValue(_ value: JSValue) throws -> JSValue {
    if case .object(let object) = value, let state = object.promiseState {
      drainMicrotasks()
      var iterations = 0
      while case .pending = state.status, iterations < 100000 {
        iterations += 1
        if !hasPendingMicrotasks { break }
        drainMicrotasks()
      }
      switch state.status {
      case .fulfilled(let inner):
        if case .object(let innerObject) = inner, innerObject.promiseState != nil {
          return try awaitValue(inner)
        }
        return inner
      case .rejected(let reason):
        throw JSError.thrown(reason)
      case .pending:
        throw JSError.runtime("await of a pending promise requires host pumping")
      }
    }
    return value
  }

  func iterateValues(_ value: JSValue) throws -> [JSValue]? {
    switch value {
    case .object(let object):
      if object.symbolProperties[JSWellKnown.iterator] != nil {
        let method = object.symbolProperties[JSWellKnown.iterator]!
        if case .function = method {
          let iterator = try callValue(
            method, thisValue: value, arguments: [], env: nil)
          return try consumeIterator(iterator)
        }
      }
      if object.mapEntries != nil {
        return object.mapEntries!.map { entry in
          .object(makeArray([entry.key, entry.value]))
        }
      }
      if object.setValues != nil { return object.setValues! }
      let lengthValue = object.get("length")
      if case .undefined = lengthValue { return nil }
      let rawCount = try toNumber(lengthValue)
      if rawCount.isNaN || rawCount <= 0 { return [] }
      let capped = min(Int(rawCount), 1048576)
      var items: [JSValue] = []
      items.reserveCapacity(capped)
      for index in 0..<capped {
        items.append(object.get(String(index)))
      }
      return items
    case .string(let text):
      return text.map { .string(String($0)) }
    default:
      return nil
    }
  }

  private func consumeIterator(_ iterator: JSValue) throws -> [JSValue]? {
    guard case .object(let object) = iterator else { return nil }
    let next = runtimeRead(object, "next")
    guard case .function = next else { return nil }
    var items: [JSValue] = []
    for _ in 0..<1048576 {
      let record = try callValue(next, thisValue: iterator, arguments: [], env: nil)
      guard case .object(let recordObject) = record else {
        throw JSError.type("Iterator result must be an object")
      }
      if recordObject.get("done").truthy { break }
      items.append(recordObject.get("value"))
    }
    return items
  }

  private func superObject() throws -> JSObject {
    guard let proto = superStack.last ?? nil else {
      throw JSError.syntax("Unexpected super")
    }
    return proto
  }

  private func buildClass(
    definition: JSClassDef, environment: JSEnvironment
  ) throws -> JSFunction {
    var superclassFunction: JSFunction?
    var parentProto: JSObject = objectPrototype
    if let heritage = definition.superclass {
      chainShortCircuited = false
      let value = try evaluate(heritage, environment: environment)
      if !value.isNullish {
        guard case .function(let parent) = value else {
          throw JSError.type("Class heritage must be a constructor")
        }
        superclassFunction = parent
        parentProto = parent.prototypeObject ?? objectPrototype
      }
    }
    let proto = JSObject(prototype: parentProto)
    var ctorParams: [JSPattern] = []
    var ctorBody: [JSStatement] = []
    for member in definition.members {
      if member.kind == .constructor, !member.isStatic {
        ctorParams = member.params
        ctorBody = member.body
        break
      }
    }
    let constructor = JSFunction(
      patterns: ctorParams, body: ctorBody, closure: environment, name: definition.name ?? "")
    constructor.isClass = true
    constructor.superclass = superclassFunction
    constructor.prototypeObject = proto
    if let parent = superclassFunction {
      constructor.staticProperties.prototype = parent.staticProperties
    }
    defineDataProperty(proto, "constructor", .function(constructor),
      writable: true, enumerable: false, configurable: true)
    if let name = definition.name, !name.isEmpty {
      defineDataProperty(constructor.staticProperties, "name", .string(name),
        writable: false, enumerable: false, configurable: true)
      constructor.name = name
    }
    var fields: [(String, JSExpression?)] = []
    for member in definition.members {
      switch member.kind {
      case .constructor:
        break
      case .method:
        let method = JSFunction(
          patterns: member.params, body: member.body, closure: environment,
          name: member.name, isAsync: member.isAsync)
        method.isMethod = true
        method.capturedThis = thisStack.last
        if member.isStatic {
          method.homeObject = constructor.staticProperties
          constructor.staticProperties.set(member.name, .function(method))
        } else {
          method.homeObject = proto
          proto.set(member.name, .function(method))
        }
      case .getter, .setter:
        let function = JSFunction(
          patterns: member.params, body: member.body, closure: environment,
          name: member.name)
        function.isMethod = true
        let holder = member.isStatic ? constructor.staticProperties : proto
        function.homeObject = holder
        function.capturedThis = thisStack.last
        if member.kind == .getter {
          defineAccessor(holder, member.name, getter: function,
            setter: holder.accessorSet[member.name], enumerable: false,
            configurable: true)
        } else {
          defineAccessor(holder, member.name, getter: holder.accessorGet[member.name],
            setter: function, enumerable: false, configurable: true)
        }
      case .field:
        if member.isStatic {
          let scope = JSEnvironment(parent: environment, kind: .function)
          let value: JSValue
          if let initializer = member.fieldInit {
            value = try evaluate(initializer, environment: scope)
          } else {
            value = .undefined
          }
          constructor.staticProperties.set(member.name, value)
        } else {
          fields.append((member.name, member.fieldInit))
        }
      }
    }
    constructor.instanceFields = fields
    return constructor
  }

  private func executeImport(
    specifiers: [JSImportSpecifier], path: String, environment: JSEnvironment
  ) throws {
    guard let module = activeModule else {
      throw JSError.syntax("Cannot use import statement outside a module")
    }
    let target = try modules.load(path: path, relativeTo: module.path, runtime: self)
    for specifier in specifiers {
      switch specifier {
      case .default(let local):
        let value = target.exports["default"] ?? .undefined
        try environment.initializeLexical(local, value: value)
      case .named(let imported, let local):
        let value = target.exports[imported] ?? .undefined
        try environment.initializeLexical(local, value: value)
      case .namespace(let local):
        let namespace = JSObject(prototype: JSObject())
        for (key, value) in target.exports { namespace.set(key, value) }
        try environment.initializeLexical(local, value: .object(namespace))
      }
    }
  }

  private func executeExport(export: JSExport, environment: JSEnvironment) throws {
    guard let module = activeModule else {
      throw JSError.syntax("Cannot use export statement outside a module")
    }
    switch export {
    case .declaration(let statement):
      let flow = try execute(statement, environment: environment)
      if case .returnValue = flow { throw JSError.syntax("Illegal return in module") }
      switch statement {
      case .function(let name?, _, _, _):
        module.exports[name] = (try? environment.checkedGet(name)) ?? .undefined
      case .classDecl(let name?, _):
        module.exports[name] = (try? environment.checkedGet(name)) ?? .undefined
      case .variable(_, let declarators):
        for (pattern, _) in declarators {
          for name in collectBoundNames(pattern) {
            module.exports[name] = (try? environment.checkedGet(name)) ?? .undefined
          }
        }
      default:
        break
      }
    case .named(let pairs):
      for pair in pairs {
        module.exports[pair.exported] = (try? environment.checkedGet(pair.local)) ?? .undefined
      }
    case .all(let from):
      if let from {
        let target = try modules.load(path: from, relativeTo: module.path, runtime: self)
        for (key, value) in target.exports { module.exports[key] = value }
      }
    case .defaultExpr(let expression):
      chainShortCircuited = false
      module.exports["default"] = try evaluate(expression, environment: environment)
    }
  }

  private func importModule(named path: String) -> JSValue {
    let capability = JSPromiseCapability(runtime: self)
    do {
      let base = activeModule?.path
      let target = try modules.load(path: path, relativeTo: base, runtime: self)
      let namespace = JSObject(prototype: JSObject())
      for (key, value) in target.exports { namespace.set(key, value) }
      capability.resolve(.object(namespace))
    } catch let error as JSError {
      capability.reject(errorValue(for: error))
    } catch {
      capability.reject(.string(error.localizedDescription))
    }
    return capability.promise
  }

  func errorValue(for error: JSError) -> JSValue {
    switch error {
    case .thrown(let value):
      return value
    case .syntax(let message):
      return constructError(type: "SyntaxError", message: message)
    case .reference(let message):
      return constructError(type: "ReferenceError", message: message)
    case .type(let message):
      return constructError(type: "TypeError", message: message)
    case .range(let message):
      return constructError(type: "RangeError", message: message)
    case .runtime(let message):
      return constructError(type: "Error", message: message)
    }
  }

  func constructError(type: String, message: String) -> JSValue {
    if let constructor = errorConstructors[type] {
      if let built = try? construct(.function(constructor), arguments: [.string(message)]) {
        return built
      }
    }
    let object = JSObject(prototype: errorPrototype)
    object.set("message", .string(message))
    object.set("name", .string(type))
    return .object(object)
  }

  func makeErrorObject(type: String, message: String) -> JSObject {
    if case .object(let object) = constructError(type: type, message: message) {
      return object
    }
    let object = JSObject(prototype: errorPrototype)
    object.set("message", .string(message))
    return object
  }

  func evaluateModuleRecord(_ source: String, record: JSModuleRecord) throws {
    let program = try JSParser(source: source).parseProgram()
    let scope = JSEnvironment(parent: globals, kind: .function)
    let previous = activeModule
    activeModule = record
    defer { activeModule = previous }
    thisStack.append(.object(globalObject))
    defer { _ = thisStack.popLast() }
    try hoist(program, in: scope)
    for statement in program {
      let flow = try execute(statement, environment: scope)
      switch flow {
      case .normal: break
      case .returnValue:
        throw JSError.syntax("Illegal return in module")
      case .breakTarget, .continueTarget:
        throw JSError.syntax("Illegal break or continue in module")
      }
    }
    drainMicrotasks()
  }

  public func dispatchEvent(type: String, target: NodeID) throws -> JSEventDispatchResult {
    guard let document = boundDocument, document.node(target) != nil else {
      return JSEventDispatchResult(defaultPrevented: false)
    }
    let normalized = type.lowercased()
    let state = JSEventState()
    var path: [NodeID] = []
    var current: NodeID? = target
    while let id = current {
      path.append(id)
      current = document.parent(of: id)
    }
    for currentTarget in path {
      let event = eventObject(
        type: normalized, target: target, currentTarget: currentTarget, document: document,
        state: state)
      for function in eventRegistry.functions(type: normalized, nodeID: currentTarget) {
        _ = try callFunction(function, arguments: [.object(event)])
        if state.propagationStopped || state.immediateStopped { break }
      }
      if state.immediateStopped { break }
      if let inline = document.node(currentTarget)?.attribute("on\(normalized)"),
        !inline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        let value = try evaluate(inline)
        if case .bool(false) = value { state.defaultPrevented = true }
      }
      if state.propagationStopped { break }
    }
    return JSEventDispatchResult(defaultPrevented: state.defaultPrevented)
  }

  func dispatchSyntheticEvent(_ event: JSObject, target: NodeID) -> Bool {
    guard let document = boundDocument, document.node(target) != nil else { return false }
    guard case .string(let rawType) = event.get("type") else { return false }
    let type = rawType.lowercased()
    let bubbles = event.get("bubbles").truthy
    var path: [NodeID] = [target]
    if bubbles {
      var current = document.parent(of: target)
      while let id = current {
        path.append(id)
        current = document.parent(of: id)
      }
    }
    for currentTarget in path {
      event.set("target", .object(domContext?.wrap(target) ?? JSObject()))
      event.set("currentTarget", .object(domContext?.wrap(currentTarget) ?? JSObject()))
      let listeners = eventRegistry.functions(type: type, nodeID: currentTarget)
      for function in listeners {
        _ = try? callFunction(function, arguments: [.object(event)])
        if case .bool(true) = event.get("__immediate") { break }
      }
      if case .bool(true) = event.get("__immediate") { break }
      if let inline = document.node(currentTarget)?.attribute("on\(type)"),
        !inline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        if case .bool(false) = (try? evaluate(inline)) ?? .undefined {
          event.set("__prevented", .bool(true))
        }
      }
      if case .bool(true) = event.get("__stopped") { break }
    }
    if case .bool(true) = event.get("__prevented") { return true }
    return false
  }

  private func eventObject(
    type: String, target: NodeID, currentTarget: NodeID, document: DOMDocument, state: JSEventState
  ) -> JSObject {
    let object = JSObject(properties: [
      "type": .string(type),
      "target": .object(
        JSDOMBindings.nodeObject(target, document: document, events: eventRegistry)),
      "currentTarget": .object(
        JSDOMBindings.nodeObject(currentTarget, document: document, events: eventRegistry)),
    ])
    object.set(
      "preventDefault",
      .function(
        JSFunction(native: { _ in
          state.defaultPrevented = true
          return .undefined
        })))
    object.set(
      "stopPropagation",
      .function(
        JSFunction(native: { _ in
          state.propagationStopped = true
          return .undefined
        })))
    return object
  }

  private func installBuiltins(document: DOMDocument?, localStorage: LocalStorage?) {
    symbolCounter = 100
    objectPrototype.prototype = nil
    let console = JSObject(prototype: objectPrototype)
    let sink: ([JSValue]) -> JSValue = { [weak self] arguments in
      self?.consoleOutput.append(arguments.map(\.description).joined(separator: " "))
      return .undefined
    }
    console.set("log", .function(JSFunction(native: sink)))
    console.set("error", .function(JSFunction(native: sink)))
    console.set("warn", .function(JSFunction(native: sink)))
    console.set("info", .function(JSFunction(native: sink)))
    console.set("debug", .function(JSFunction(native: sink)))
    globals.define("console", value: .object(console))
    globalObject.set("console", .object(console))
    globalObject.set("globalThis", .object(globalObject))
    globals.define("globalThis", value: .object(globalObject))
    JSBuiltins.install(into: self)
    JSPromise.install(into: self)
    JSBuiltins.installTypedArrays(into: self)
    installFunctionConstructor()
    installEval()
    installGlobals()
    installTimerGlobals()
    installFetchGlobals()
    installWindow(document: document, localStorage: localStorage)
  }

  private func installFunctionConstructor() {
    let constructor = JSFunction(native: { [weak self] args in
      guard let self else { return .undefined }
      let params = args.dropLast().map { (try? self.toString($0)) ?? "" }
      let text = args.last.flatMap { (try? self.toString($0)) ?? "" } ?? ""
      let patterns = try params.map { name -> JSPattern in
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
          throw JSError.syntax("Invalid parameter name")
        }
        return .identifier(trimmed, nil)
      }
      let body = try JSParser(source: text).parseProgram()
      return .function(
        JSFunction(patterns: patterns, body: body, closure: self.globals, name: "anonymous"))
    }, name: "Function")
    constructor.prototypeObject = JSObject(prototype: objectPrototype)
    globals.define("Function", value: .function(constructor))
    globalObject.set("Function", .function(constructor))
  }

  private func installEval() {
    let evalFunction = JSFunction(native: { [weak self] _ in .undefined }, name: "eval")
    _ = evalFunction
    let direct = JSFunction(nativeMethod: { [weak self] _, args in
      guard let self else { return .undefined }
      guard let source = args.first, case .string(let text) = source else {
        return args.first ?? .undefined
      }
      guard self.evalAllowed() else {
        throw JSError.runtime("eval is blocked by content security policy")
      }
      let program = try JSParser(source: text).parseProgram()
      let scope = JSEnvironment(parent: self.globals, kind: .function)
      try self.hoist(program, in: scope)
      var last: JSValue = .undefined
      for statement in program {
        let flow = try self.execute(statement, environment: scope)
        switch flow {
        case .normal(let value): last = value
        case .returnValue(let value): last = value
        case .breakTarget, .continueTarget:
          throw JSError.syntax("Illegal break or continue outside a loop")
        }
      }
      self.drainMicrotasks()
      return last
    }, name: "eval")
    globals.define("eval", value: .function(direct))
    globalObject.set("eval", .function(direct))
  }

  private func installGlobals() {
    globals.define(
      "parseInt",
      value: .function(
        JSFunction(native: { [weak self] args in
          guard let self else { return .undefined }
          guard let first = args.first else { return .number(.nan) }
          let text = ((try? self.toString(first)) ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
          var radix = 10
          if args.count > 1, case .number(let value) = args[1], value != 0 {
            radix = Int(value)
          }
          if radix < 2 || radix > 36 { return .number(.nan) }
          var body = text
          var negative = false
          if body.hasPrefix("-") {
            negative = true
            body = String(body.dropFirst())
          } else if body.hasPrefix("+") {
            body = String(body.dropFirst())
          }
          if radix == 16, body.lowercased().hasPrefix("0x") {
            body = String(body.dropFirst(2))
          }
          let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
          var value = 0.0
          var consumed = false
          for character in body.lowercased() {
            guard let position = digits.firstIndex(of: character) else { break }
            let digit = digits.distance(from: digits.startIndex, to: position)
            if digit >= radix { break }
            value = value * Double(radix) + Double(digit)
            consumed = true
          }
          guard consumed else { return .number(.nan) }
          return .number(negative ? -value : value)
        }, name: "parseInt")))
    globals.define(
      "parseFloat",
      value: .function(
        JSFunction(native: { [weak self] args in
          guard let self, let first = args.first else { return .number(.nan) }
          let text = ((try? self.toString(first)) ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
          var prefix = ""
          var index = text.startIndex
          if index < text.endIndex, text[index] == "+" || text[index] == "-" {
            prefix.append(text[index])
            index = text.index(after: index)
          }
          let rest = String(text[index...])
          if rest.hasPrefix("Infinity") { return .number(prefix == "-" ? -.infinity : .infinity) }
          var scanned = prefix
          var seenDot = false
          var seenDigit = false
          var position = index
          while position < text.endIndex {
            let character = text[position]
            if character.isNumber {
              seenDigit = true
              scanned.append(character)
            } else if character == ".", !seenDot {
              seenDot = true
              scanned.append(character)
            } else {
              break
            }
            position = text.index(after: position)
          }
          if position < text.endIndex, text[position] == "e" || text[position] == "E" {
            var exponent = String(text[position])
            var cursor = text.index(after: position)
            if cursor < text.endIndex, text[cursor] == "+" || text[cursor] == "-" {
              exponent.append(text[cursor])
              cursor = text.index(after: cursor)
            }
            var digits = ""
            while cursor < text.endIndex, text[cursor].isNumber {
              digits.append(text[cursor])
              cursor = text.index(after: cursor)
            }
            if !digits.isEmpty {
              scanned.append(exponent)
              scanned.append(digits)
            }
          }
          guard seenDigit, let value = Double(scanned) else { return .number(.nan) }
          return .number(value)
        }, name: "parseFloat")))
    globals.define(
      "isNaN",
      value: .function(
        JSFunction(native: { [weak self] args in
          guard let self else { return .undefined }
          return .bool((try? self.toNumber(args.first ?? .undefined))?.isNaN ?? true)
        }, name: "isNaN")))
    globals.define(
      "isFinite",
      value: .function(
        JSFunction(native: { [weak self] args in
          guard let self else { return .undefined }
          guard let number = try? self.toNumber(args.first ?? .undefined) else {
            return .bool(false)
          }
          return .bool(number.isFinite)
        }, name: "isFinite")))
    globals.define(
      "decodeURIComponent",
      value: .function(
        JSFunction(native: { [weak self] args in
          guard let self else { return .undefined }
          let text = try self.toString(args.first ?? .undefined)
          return .string(text.removingPercentEncoding ?? text)
        }, name: "decodeURIComponent")))
    globals.define(
      "encodeURIComponent",
      value: .function(
        JSFunction(native: { [weak self] args in
          guard let self else { return .undefined }
          let text = try self.toString(args.first ?? .undefined)
          let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))
          return .string(text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text)
        }, name: "encodeURIComponent")))
    globals.define(
      "queueMicrotask",
      value: .function(
        JSFunction(native: { [weak self] args in
          if case .function(let callback) = args.first {
            self?.queueMicrotask { [weak self] in
              _ = try? self?.callFunction(callback, arguments: [])
            }
          }
          return .undefined
        }, name: "queueMicrotask")))
    for (name, value) in globalsSnapshot() {
      globalObject.set(name, value)
    }
  }

  private func globalsSnapshot() -> [(String, JSValue)] {
    var pairs: [(String, JSValue)] = []
    for name in [
      "parseInt", "parseFloat", "isNaN", "isFinite", "decodeURIComponent",
      "encodeURIComponent", "queueMicrotask", "Function", "eval", "setTimeout",
      "clearTimeout", "setInterval", "clearInterval", "fetch", "Headers", "Request",
      "Response",
    ] {
      if let value = globals.get(name) { pairs.append((name, value)) }
    }
    return pairs
  }

  private func installWindow(document: DOMDocument?, localStorage: LocalStorage?) {
    guard let document else { return }
    let context = JSDOMContext(runtime: self, document: document, events: eventRegistry)
    domContext = context
    let documentObject = JSDOMBindings.documentObject(context: context)
    var localStorageObject: JSObject?
    if let localStorage {
      localStorageObject = JSStorageBindings.localStorageObject(localStorage)
    }
    let sessionStorageObject = JSStorageBindings.localStorageObject(sessionStorage)
    let window = JSDOMEvents.makeWindow(
      context: context, document: documentObject,
      localStorage: localStorageObject, sessionStorage: sessionStorageObject)
    if let console = globalObject.get("console") as JSValue? {
      window.set("console", console)
    }
    for name in [
      "setTimeout", "clearTimeout", "setInterval", "clearInterval", "queueMicrotask",
      "fetch", "Headers", "Request", "Response",
    ] {
      if let value = globals.get(name) { window.set(name, value) }
    }
    globals.define("document", value: .object(documentObject))
    globals.define("window", value: .object(window))
    globals.define("self", value: .object(window))
    globalObject.set("document", .object(documentObject))
    globalObject.set("window", .object(window))
    globalObject.set("self", .object(window))
    if let localStorageObject {
      globals.define("localStorage", value: .object(localStorageObject))
      globalObject.set("localStorage", .object(localStorageObject))
    }
    globals.define("sessionStorage", value: .object(sessionStorageObject))
    globalObject.set("sessionStorage", .object(sessionStorageObject))
    JSDOMEvents.installEventGlobals(
      holder: globalObject, context: context, runtime: self)
    globals.define(
      "Event",
      value: globalObject.get("Event"))
    globals.define(
      "CustomEvent", value: globalObject.get("CustomEvent"))
    globals.define(
      "MouseEvent", value: globalObject.get("MouseEvent"))
    globals.define(
      "KeyboardEvent", value: globalObject.get("KeyboardEvent"))
  }
}

extension JSArrowBody {
  var statements: [JSStatement] {
    switch self {
    case .expression: return []
    case .block(let statements): return statements
    }
  }
}

public enum JSWellKnown {
  public static let iterator = 1
  public static let hasInstance = 2
  public static let toStringTag = 3
  public static let species = 4
  public static let asyncIterator = 5
}

public protocol JSTimerHost: AnyObject {
  func setTimeout(milliseconds: Double, repeats: Bool, callback: JSFunction) -> Double
  func clearTimeout(id: Double)
}

public protocol JSPumpableTimers: AnyObject {
  func pump(now: Double) -> Int
}