import DOM
import Foundation

public final class JSPromiseState {
  public enum Status {
    case pending
    case fulfilled(JSValue)
    case rejected(JSValue)
  }

  public var status: Status = .pending
  private var fulfillReactions: [(JSValue) -> Void] = []
  private var rejectReactions: [(JSValue) -> Void] = []
  public var hasHandler = false

  public init() {}

  public func onSettled(fulfill: @escaping (JSValue) -> Void, reject: @escaping (JSValue) -> Void) {
    hasHandler = true
    switch status {
    case .pending:
      fulfillReactions.append(fulfill)
      rejectReactions.append(reject)
    case .fulfilled(let value):
      fulfill(value)
    case .rejected(let reason):
      reject(reason)
    }
  }

  public func fulfill(_ value: JSValue) {
    guard case .pending = status else { return }
    status = .fulfilled(value)
    let reactions = fulfillReactions
    fulfillReactions.removeAll()
    rejectReactions.removeAll()
    for reaction in reactions { reaction(value) }
  }

  public func reject(_ reason: JSValue) {
    guard case .pending = status else { return }
    status = .rejected(reason)
    let reactions = rejectReactions
    fulfillReactions.removeAll()
    rejectReactions.removeAll()
    for reaction in reactions { reaction(reason) }
  }
}

public final class JSPromiseCapability {
  public let promise: JSValue
  private let state: JSPromiseState
  private weak var runtime: JSRuntime?

  public init(runtime: JSRuntime) {
    self.runtime = runtime
    let object = JSObject(prototype: runtime.promisePrototype)
    let state = JSPromiseState()
    object.promiseState = state
    self.state = state
    self.promise = .object(object)
  }

  public func resolve(_ value: JSValue) {
    if let runtime, case .object(let object) = value, object.promiseState != nil {
      state.onSettled(
        fulfill: { [weak runtime] inner in
          runtime?.settleCapability(self, fulfilled: inner)
        },
        reject: { [weak runtime] reason in
          runtime?.settleCapability(self, rejected: reason)
        })
      return
    }
    runtime?.settleCapability(self, fulfilled: value)
  }

  public func reject(_ reason: JSValue) {
    runtime?.settleCapability(self, rejected: reason)
  }

  func settleFulfilled(_ value: JSValue) { state.fulfill(value) }
  func settleRejected(_ reason: JSValue) {
    state.reject(reason)
    if !state.hasHandler {
      runtime?.reportUnhandledRejection(reason)
    }
  }
}

public enum JSPromise {
  public static func install(into runtime: JSRuntime) {
    let proto = runtime.promisePrototype
    proto.prototype = runtime.objectPrototype
    let constructor = JSFunction(native: { [weak runtime] args in
      guard let runtime else { return .undefined }
      let capability = JSPromiseCapability(runtime: runtime)
      if case .function(let executor) = args.first {
        do {
          _ = try runtime.callFunction(
            executor,
            arguments: [
              .function(
                JSFunction(native: { values in
                  capability.resolve(values.first ?? .undefined)
                  return .undefined
                })),
              .function(
                JSFunction(native: { values in
                  capability.reject(values.first ?? .undefined)
                  return .undefined
                })),
            ])
        } catch let error as JSError {
          capability.reject(runtime.errorValue(for: error))
        } catch {
          capability.reject(.string(error.localizedDescription))
        }
      } else {
        throw JSError.type("Promise executor must be callable")
      }
      return capability.promise
    }, name: "Promise")
    constructor.prototypeObject = runtime.promisePrototype
    runtime.promisePrototype.set("constructor", .function(constructor))
    defineNativeMethod(proto, "then", 2, runtime) { runtime, thisValue, args in
      guard case .object(let object) = thisValue, let state = object.promiseState else {
        throw JSError.type("then called on incompatible receiver")
      }
      let derived = JSPromiseCapability(runtime: runtime)
      let onFulfilled = args.first
      let onRejected = args.count > 1 ? args[1] : .undefined
      state.hasHandler = true
      let fulfill: (JSValue) -> Void = { [weak runtime] value in
        guard let runtime else { return }
        runtime.queueMicrotask {
          do {
            if case .function(let handler) = onFulfilled {
              let result = try runtime.callFunction(handler, arguments: [value])
              derived.resolve(result)
            } else {
              derived.resolve(value)
            }
          } catch let error as JSError {
            derived.reject(runtime.errorValue(for: error))
          } catch {
            derived.reject(.string(error.localizedDescription))
          }
        }
      }
      let reject: (JSValue) -> Void = { [weak runtime] reason in
        guard let runtime else { return }
        runtime.queueMicrotask {
          do {
            if case .function(let handler) = onRejected {
              let result = try runtime.callFunction(handler, arguments: [reason])
              derived.resolve(result)
            } else {
              derived.reject(reason)
            }
          } catch let error as JSError {
            derived.reject(runtime.errorValue(for: error))
          } catch {
            derived.reject(.string(error.localizedDescription))
          }
        }
      }
      state.onSettled(fulfill: fulfill, reject: reject)
      return derived.promise
    }
    defineNativeMethod(proto, "catch", 1, runtime) { runtime, thisValue, args in
      let thenMethod = runtime.runtimeGet(thisValue, "then")
      return try runtime.callValue(
        thenMethod, thisValue: thisValue, arguments: [.undefined, args.first ?? .undefined])
    }
    defineNativeMethod(proto, "finally", 1, runtime) { runtime, thisValue, args in
      let handler = args.first ?? .undefined
      let wrapFulfilled = JSFunction(native: { [weak runtime] values in
        guard let runtime else { return .undefined }
        if case .function(let cleanup) = handler {
          _ = try runtime.callFunction(cleanup, arguments: [])
        }
        return values.first ?? .undefined
      })
      let wrapRejected = JSFunction(native: { [weak runtime] values in
        guard let runtime else { return .undefined }
        if case .function(let cleanup) = handler {
          _ = try runtime.callFunction(cleanup, arguments: [])
        }
        throw JSError.thrown(values.first ?? .undefined)
      })
      let thenMethod = runtime.runtimeGet(thisValue, "then")
      return try runtime.callValue(
        thenMethod, thisValue: thisValue,
        arguments: [.function(wrapFulfilled), .function(wrapRejected)])
    }
    addStatic(constructor, "resolve", runtime) { runtime, args in
      let capability = JSPromiseCapability(runtime: runtime)
      capability.resolve(args.first ?? .undefined)
      return capability.promise
    }
    addStatic(constructor, "reject", runtime) { runtime, args in
      let capability = JSPromiseCapability(runtime: runtime)
      capability.reject(args.first ?? .undefined)
      return capability.promise
    }
    addStatic(constructor, "all", runtime) { runtime, args in
      try allCombinator(runtime: runtime, args: args, mode: .all)
    }
    addStatic(constructor, "allSettled", runtime) { runtime, args in
      try allCombinator(runtime: runtime, args: args, mode: .allSettled)
    }
    addStatic(constructor, "race", runtime) { runtime, args in
      guard let items = try runtime.iterateValues(args.first ?? .undefined) else {
        throw JSError.type("Argument is not iterable")
      }
      let capability = JSPromiseCapability(runtime: runtime)
      if items.isEmpty { return capability.promise }
      for item in items {
        if case .object(let object) = item, let state = object.promiseState {
          state.hasHandler = true
          state.onSettled(
            fulfill: { value in capability.resolve(value) },
            reject: { reason in capability.reject(reason) })
        } else {
          capability.resolve(item)
          break
        }
      }
      return capability.promise
    }
    addStatic(constructor, "any", runtime) { runtime, args in
      guard let items = try runtime.iterateValues(args.first ?? .undefined) else {
        throw JSError.type("Argument is not iterable")
      }
      let capability = JSPromiseCapability(runtime: runtime)
      if items.isEmpty {
        capability.reject(
          runtime.constructError(
            type: "AggregateError", message: "All promises were rejected"))
        return capability.promise
      }
      var remaining = items.count
      var errors: [JSValue] = []
      for item in items {
        let fulfill: (JSValue) -> Void = { value in capability.resolve(value) }
        let reject: (JSValue) -> Void = { reason in
          errors.append(reason)
          remaining -= 1
          if remaining == 0 {
            let aggregate = runtime.constructError(
              type: "AggregateError", message: "All promises were rejected")
            if case .object(let object) = aggregate {
              object.set("errors", .object(runtime.makeArray(errors)))
            }
            capability.reject(aggregate)
          }
        }
        if case .object(let object) = item, let state = object.promiseState {
          state.hasHandler = true
          state.onSettled(fulfill: fulfill, reject: reject)
        } else {
          capability.resolve(item)
          break
        }
      }
      return capability.promise
    }
    runtime.globals.define("Promise", value: .function(constructor))
  }

  private enum AllMode {
    case all
    case allSettled
  }

  private static func allCombinator(
    runtime: JSRuntime, args: [JSValue], mode: AllMode
  ) throws -> JSValue {
    guard let items = try runtime.iterateValues(args.first ?? .undefined) else {
      throw JSError.type("Argument is not iterable")
    }
    let capability = JSPromiseCapability(runtime: runtime)
    if items.isEmpty {
      capability.resolve(.object(runtime.makeArray([])))
      return capability.promise
    }
    var results = Array<JSValue?>(repeating: nil, count: items.count)
    var remaining = items.count
    for (index, item) in items.enumerated() {
      let fulfill: (JSValue) -> Void = { value in
        switch mode {
        case .all:
          results[index] = value
        case .allSettled:
          let record = JSObject(prototype: runtime.objectPrototype)
          record.set("status", .string("fulfilled"))
          record.set("value", value)
          results[index] = .object(record)
        }
        remaining -= 1
        if remaining == 0 {
          capability.resolve(.object(runtime.makeArray(results.map { $0 ?? .undefined })))
        }
      }
      let reject: (JSValue) -> Void = { reason in
        switch mode {
        case .all:
          capability.reject(reason)
        case .allSettled:
          let record = JSObject(prototype: runtime.objectPrototype)
          record.set("status", .string("rejected"))
          record.set("reason", reason)
          results[index] = .object(record)
          remaining -= 1
          if remaining == 0 {
            capability.resolve(.object(runtime.makeArray(results.map { $0 ?? .undefined })))
          }
        }
      }
      if case .object(let object) = item, let state = object.promiseState {
        state.hasHandler = true
        state.onSettled(fulfill: fulfill, reject: reject)
      } else {
        fulfill(item)
      }
      if case .rejected = (itemPromiseState(item)?.status), mode == .all { break }
    }
    return capability.promise
  }

  private static func itemPromiseState(_ value: JSValue) -> JSPromiseState? {
    if case .object(let object) = value { return object.promiseState }
    return nil
  }

  private static func addStatic(
    _ constructor: JSFunction, _ name: String, _ runtime: JSRuntime,
    _ body: @escaping (JSRuntime, [JSValue]) throws -> JSValue
  ) {
    let function = JSFunction(native: { [weak runtime] args in
      guard let runtime else { return .undefined }
      return try body(runtime, args)
    }, name: name)
    constructor.staticProperties.set(name, .function(function))
  }

  private static func defineNativeMethod(
    _ object: JSObject, _ name: String, _ arity: Int, _ runtime: JSRuntime,
    _ body: @escaping (JSRuntime, JSValue, [JSValue]) throws -> JSValue
  ) {
    let function = JSFunction(nativeMethod: { [weak runtime] thisValue, args in
      guard let runtime else { return .undefined }
      return try body(runtime, thisValue, args)
    }, name: name)
    object.set(name, .function(function))
  }
}
