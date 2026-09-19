import DOM
import Foundation

extension JSBuiltins {
  static func installErrors(into runtime: JSRuntime) {
    let base = runtime.errorPrototype
    base.set("name", .string("Error"))
    base.set("message", .string(""))
    for (type, parent) in [
      ("Error", nil as JSObject?), ("TypeError", base), ("RangeError", base),
      ("SyntaxError", base), ("ReferenceError", base), ("URIError", base),
      ("EvalError", base), ("AggregateError", base),
    ] as [(String, JSObject?)] {
      let parentProto = parent ?? runtime.objectPrototype
      let proto: JSObject
      if type == "Error" {
        proto = base
      } else {
        proto = JSObject(prototype: parentProto)
      }
      proto.set("name", .string(type))
      proto.set("message", .string(""))
      let constructor = makeConstructor(
        runtime: runtime, name: type,
        call: { [weak runtime] args in
          guard let runtime else { return .undefined }
          return runtime.constructError(
            type: type, message: args.first.flatMap { try? runtime.toString($0) } ?? "")
        },
        construct: { [weak runtime] args in
          guard let runtime else { return .undefined }
          let object = JSObject(
            prototype: runtime.errorConstructors[type]?.prototypeObject ?? runtime.errorPrototype)
          let message = args.first.flatMap { try? runtime.toString($0) } ?? ""
          object.set("message", .string(message))
          object.set("name", .string(type))
          if args.count > 1, case .object(let options) = args[1],
            options.hasOwn("cause")
          {
            object.set("cause", options.get("cause"))
          }
          return .object(object)
        },
        parentPrototype: runtime.objectPrototype)
      constructor.prototypeObject = proto
      proto.set("constructor", .function(constructor))
      runtime.errorConstructors[type] = constructor
      publish(into: runtime, type, .function(constructor))
    }
  }

  static func installJSON(into runtime: JSRuntime) {
    let json = JSObject(prototype: runtime.objectPrototype)
    json.defineNative("parse") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      let text = try runtime.toString(args.first ?? .undefined)
      guard let data = text.data(using: .utf8) else {
        throw JSError.syntax("Invalid JSON")
      }
      do {
        let parsed = try JSONSerialization.jsonObject(with: data, options: [.allowFragments])
        return try fromJSON(parsed, runtime: runtime)
      } catch {
        throw JSError.syntax("Invalid JSON")
      }
    }
    json.defineNative("stringify") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      let value = args.first ?? .undefined
      let replacer = args.count > 1 ? args[1] : .undefined
      let space: String?
      if args.count > 2 {
        if case .number(let number) = args[2] {
          space = String(repeating: " ", count: min(10, max(0, Int(number))))
        } else if case .string(let text) = args[2] {
          space = String(text.prefix(10))
        } else {
          space = nil
        }
      } else {
        space = nil
      }
      var seen = Set<ObjectIdentifier>()
      guard let text = try stringifyJSON(
        value, key: "", holder: nil, replacer: replacer, space: space, indent: "",
        runtime: runtime, seen: &seen)
      else {
        return .undefined
      }
      return .string(text)
    }
    publish(into: runtime, "JSON", .object(json))
  }

  static func fromJSON(_ value: Any, runtime: JSRuntime) throws -> JSValue {
    switch value {
    case is NSNull: return .null
    case let number as NSNumber:
      if number === kCFBooleanTrue as NSNumber { return .bool(true) }
      if number === kCFBooleanFalse as NSNumber { return .bool(false) }
      return .number(number.doubleValue)
    case let text as String: return .string(text)
    case let array as [Any]:
      return .object(runtime.makeArray(try array.map { try fromJSON($0, runtime: runtime) }))
    case let dictionary as [String: Any]:
      let object = JSObject(prototype: runtime.objectPrototype)
      for (key, entry) in dictionary {
        object.set(key, try fromJSON(entry, runtime: runtime))
      }
      return .object(object)
    default:
      throw JSError.syntax("Invalid JSON value")
    }
  }

  static func stringifyJSON(
    _ value: JSValue, key: String, holder: JSObject?, replacer: JSValue, space: String?,
    indent: String, runtime: JSRuntime, seen: inout Set<ObjectIdentifier>
  ) throws -> String? {
    var current = value
    if let holder {
      current = holder.get(key)
    }
    if case .object(let object) = current {
      let toJSON = runtime.runtimeRead(object, "toJSON")
      if case .function = toJSON {
        current = try runtime.callValue(
          toJSON, thisValue: current, arguments: [.string(key)])
      }
    }
    if case .function(let replacerFunction) = replacer {
      current = try runtime.callValue(
        .function(replacerFunction), thisValue: holder.map { .object($0) } ?? .undefined,
        arguments: [key.isEmpty ? .string("") : .string(key), current])
    }
    switch current {
    case .undefined, .symbol: return nil
    case .function: return nil
    case .null: return "null"
    case .bool(let flag): return flag ? "true" : "false"
    case .number(let number):
      if number.isNaN || number.isInfinite { return "null" }
      return try runtime.toString(current)
    case .bigint: throw JSError.type("Cannot serialize BigInt")
    case .string(let text): return jsonQuoted(text)
    case .object(let object):
      let id = ObjectIdentifier(object)
      if seen.contains(id) { throw JSError.type("Cyclic value") }
      seen.insert(id)
      defer { seen.remove(id) }
      if let entries = object.mapEntries {
        _ = entries
        return "{}"
      }
      if object.setValues != nil { return "{}" }
      if object.isArrayBuffer { return "{}" }
      let lengthValue = object.get("length")
      if isJSONList(object), case .number = lengthValue {
        var parts: [String] = []
        let count = max(0, Int(try runtime.toNumber(lengthValue)))
        for index in 0..<min(count, 1048576) {
          let item = object.get(String(index))
          if let text = try stringifyJSON(
            item, key: String(index), holder: object, replacer: replacer, space: space,
            indent: childIndent(indent, space: space), runtime: runtime, seen: &seen)
          {
            parts.append(text)
          } else {
            parts.append("null")
          }
        }
        return jsonArray(parts, space: space, indent: indent)
      }
      var keys: [String] = []
      if case .object(let replacerList) = replacer {
        let length = replacerList.get("length")
        if case .number = length {
          let count = max(0, Int((try? runtime.toNumber(length)) ?? 0))
          for index in 0..<min(count, 1024) {
            keys.append(try runtime.toString(replacerList.get(String(index))))
          }
        }
      } else {
        keys = object.ownEnumerableKeys()
      }
      var parts: [String] = []
      for child in keys {
        guard let text = try stringifyJSON(
          .undefined, key: child, holder: object, replacer: replacer, space: space,
          indent: childIndent(indent, space: space), runtime: runtime, seen: &seen)
        else {
          continue
        }
        if let space {
          parts.append("\(jsonQuoted(child)): \(text)")
        } else {
          parts.append("\(jsonQuoted(child)):\(text)")
        }
      }
      return jsonObject(parts, space: space, indent: indent)
    }
  }

  static func isJSONList(_ object: JSObject) -> Bool {
    if case .number = object.get("length") {
      var count = 0
      for key in object.properties.keys {
        if jsArrayIndex(key) != nil { count += 1 } else if key != "length" { return false }
      }
      return true
    }
    return false
  }

  static func childIndent(_ indent: String, space: String?) -> String {
    guard let space else { return "" }
    return indent + space
  }

  static func jsonArray(_ parts: [String], space: String?, indent: String) -> String {
    guard let space, !parts.isEmpty else {
      return "[\(parts.joined(separator: ","))]"
    }
    let child = indent + space
    return "[\n\(child + parts.joined(separator: ",\n\(child)"))\n\(indent)]"
  }

  static func jsonObject(_ parts: [String], space: String?, indent: String) -> String {
    guard let space, !parts.isEmpty else {
      return "{\(parts.joined(separator: ","))}"
    }
    let child = indent + space
    return "{\n\(child + parts.joined(separator: ",\n\(child)"))\n\(indent)}"
  }

  static func jsonQuoted(_ text: String) -> String {
    var result = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": result += "\\\""
      case "\\": result += "\\\\"
      case "\n": result += "\\n"
      case "\r": result += "\\r"
      case "\t": result += "\\t"
      case "\u{8}": result += "\\b"
      case "\u{C}": result += "\\f"
      default:
        if scalar.value < 0x20 {
          result += String(format: "\\u%04x", scalar.value)
        } else {
          result.append(Character(scalar))
        }
      }
    }
    result += "\""
    return result
  }

  static func installMath(into runtime: JSRuntime) {
    let math = JSObject(prototype: runtime.objectPrototype)
    let constants: [(String, Double)] = [
      ("E", M_E), ("LN2", log(2)), ("LN10", log(10)), ("LOG2E", log2(M_E)),
      ("LOG10E", log10(M_E)), ("PI", Double.pi), ("SQRT1_2", sqrt(0.5)),
      ("SQRT2", sqrt(2)),
    ]
    for (name, value) in constants {
      runtime.defineDataProperty(math, name, .number(value),
        writable: false, enumerable: false, configurable: false)
    }
    func unary(_ name: String, _ body: @escaping (Double) -> Double) {
      math.defineNative(name) { [weak runtime] _, args in
        guard let runtime else { return .undefined }
        return .number(body(try runtime.toNumber(args.first ?? .undefined)))
      }
    }
    unary("abs", { abs($0) })
    unary("acos", { acos($0) })
    unary("acosh", { acosh($0) })
    unary("asin", { asin($0) })
    unary("asinh", { asinh($0) })
    unary("atan", { atan($0) })
    unary("atanh", { atanh($0) })
    unary("cbrt", { cbrt($0) })
    unary("ceil", { ceil($0) })
    math.defineNative("clz32") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      let value = try runtime.toNumber(args.first ?? .undefined)
      if value.isNaN { return .number(32) }
      return .number(Double(runtime.toUint32(value).leadingZeroBitCount))
    }
    unary("cos", { cos($0) })
    unary("cosh", { cosh($0) })
    unary("exp", { exp($0) })
    unary("expm1", { expm1($0) })
    unary("floor", { floor($0) })
    unary("fround", { Double(Float($0)) })
    unary("log", { log($0) })
    unary("log1p", { log1p($0) })
    unary("log2", { log2($0) })
    unary("log10", { log10($0) })
    unary("round", { $0.rounded() })
    unary("sign", { $0.isNaN ? .nan : ($0 == 0 ? $0 : ($0 > 0 ? 1 : -1)) })
    unary("sin", { sin($0) })
    unary("sinh", { sinh($0) })
    unary("sqrt", { sqrt($0) })
    unary("tan", { tan($0) })
    unary("tanh", { tanh($0) })
    unary("trunc", { trunc($0) })
    math.defineNative("atan2") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      let first = try runtime.toNumber(args.first ?? .undefined)
      let second = args.count > 1 ? try runtime.toNumber(args[1]) : .nan
      return .number(atan2(first, second))
    }
    math.defineNative("hypot") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      var sum = 0.0
      for argument in args {
        let value = try runtime.toNumber(argument)
        sum += value * value
      }
      return .number(sqrt(sum))
    }
    math.defineNative("imul") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      let first = args.first.flatMap { try? runtime.toNumber($0) } ?? 0
      let second = args.count > 1 ? (try? runtime.toNumber(args[1])) ?? 0 : 0
      let product = Int64(runtime.toInt32(first)) * Int64(runtime.toInt32(second))
      return .number(Double(Int32(truncatingIfNeeded: product)))
    }
    math.defineNative("max") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      var best = -Double.infinity
      for argument in args {
        let value = try runtime.toNumber(argument)
        if value.isNaN { return .number(.nan) }
        best = max(best, value)
      }
      return .number(best)
    }
    math.defineNative("min") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      var best = Double.infinity
      for argument in args {
        let value = try runtime.toNumber(argument)
        if value.isNaN { return .number(.nan) }
        best = min(best, value)
      }
      return .number(best)
    }
    math.defineNative("pow") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      let first = try runtime.toNumber(args.first ?? .undefined)
      let second = args.count > 1 ? try runtime.toNumber(args[1]) : .nan
      return .number(pow(first, second))
    }
    math.defineNative("random") { _, _ in .number(Double.random(in: 0..<1)) }
    publish(into: runtime, "Math", .object(math))
  }

  static func installSymbol(into runtime: JSRuntime) {
    let proto = runtime.symbolPrototype
    proto.defineNative("toString") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .symbol(let id) = thisArg else {
        throw JSError.type("Receiver must be a Symbol")
      }
      if let text = runtime.symbolDescriptions[id] {
        return .string("Symbol(\(text))")
      }
      return .string("Symbol()")
    }
    proto.defineNative("valueOf") { thisArg, _ in
      guard case .symbol = thisArg else {
        throw JSError.type("Receiver must be a Symbol")
      }
      return thisArg
    }
    let constructor = makeConstructor(
      runtime: runtime, name: "Symbol",
      call: { [weak runtime] args in
        guard let runtime else { return .undefined }
        let description = try args.first.map { try runtime.toString($0) }
        return runtime.newSymbol(description: description)
      },
      construct: { _ in
        throw JSError.type("Symbol is not a constructor")
      })
    constructor.constructNative = { _ in
      throw JSError.type("Symbol is not a constructor")
    }
    let statics = constructor.staticProperties
    statics.defineNative("for") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      let key = try runtime.toString(args.first ?? .undefined)
      if let id = runtime.symbolForRegistry[key] { return .symbol(id) }
      let value = runtime.newSymbol(description: key)
      if case .symbol(let id) = value { runtime.symbolForRegistry[key] = id }
      return value
    }
    statics.defineNative("keyFor") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard case .symbol(let id) = args.first else {
        throw JSError.type("Argument must be a Symbol")
      }
      for (key, stored) in runtime.symbolForRegistry where stored == id {
        return .string(key)
      }
      return .undefined
    }
    for (name, id) in [
      ("iterator", JSWellKnown.iterator), ("hasInstance", JSWellKnown.hasInstance),
      ("toStringTag", JSWellKnown.toStringTag), ("species", JSWellKnown.species),
      ("asyncIterator", JSWellKnown.asyncIterator),
    ] as [(String, Int)] {
      statics.set(name, .symbol(id))
    }
    publish(into: runtime, "Symbol", .function(constructor))
  }
}
