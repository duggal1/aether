import DOM
import Foundation

extension JSBuiltins {
  static func isJSArray(_ value: JSValue, runtime: JSRuntime) -> Bool {
    guard case .object(let object) = value else { return false }
    var current: JSObject? = object
    var depth = 0
    while let node = current, depth < 64 {
      depth += 1
      if node === runtime.arrayPrototype { return true }
      current = node.prototype
    }
    return false
  }

  static func arrayLength(_ object: JSObject, runtime: JSRuntime) throws -> Int {
    let raw = try runtime.toNumber(object.get("length"))
    if raw.isNaN || raw <= 0 { return 0 }
    return min(Int(raw), 1048576)
  }

  static func installArray(into runtime: JSRuntime) {
    let proto = runtime.arrayPrototype
    let constructor = makeConstructor(
      runtime: runtime, name: "Array",
      call: { [weak runtime] args in
        guard let runtime else { return .undefined }
        return try buildNewArray(runtime: runtime, args: args)
      },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        return try buildNewArray(runtime: runtime, args: args)
      })
    publish(into: runtime, "Array", .function(constructor))
    constructor.prototypeObject = runtime.arrayPrototype
    runtime.arrayPrototype.set("constructor", .function(constructor))
    let statics = constructor.staticProperties
    statics.defineNative("isArray") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard let first = args.first else { return .bool(false) }
      return .bool(isJSArray(first, runtime: runtime))
    }
    statics.defineNative("of") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      return .object(runtime.makeArray(args))
    }
    statics.defineNative("from") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard let first = args.first, !first.isNullish else {
        return .object(runtime.makeArray([]))
      }
      var items: [JSValue]
      if let iterated = try runtime.iterateValues(first) {
        items = iterated
      } else if case .object(let object) = first {
        let count = try arrayLength(object, runtime: runtime)
        items = (0..<count).map { object.get(String($0)) }
      } else {
        throw JSError.type("Argument is not iterable")
      }
      if args.count > 1, case .function = args[1] {
        let mapper = args[1]
        let thisArg = args.count > 2 ? args[2] : .undefined
        var mapped: [JSValue] = []
        for (index, item) in items.enumerated() {
          mapped.append(
            try runtime.callValue(mapper, thisValue: thisArg,
              arguments: [item, .number(Double(index))]))
        }
        items = mapped
      }
      return .object(runtime.makeArray(items))
    }
    proto.defineNative("push") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      var length = try arrayLength(object, runtime: runtime)
      for argument in args {
        object.set(String(length), argument)
        length += 1
      }
      object.set("length", .number(Double(length)))
      return .number(Double(length))
    }
    proto.defineNative("pop") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = try arrayLength(object, runtime: runtime)
      if length == 0 {
        object.set("length", .number(0))
        return .undefined
      }
      let value = object.get(String(length - 1))
      object.deleteOwn(String(length - 1))
      object.set("length", .number(Double(length - 1)))
      return value
    }
    proto.defineNative("shift") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = try arrayLength(object, runtime: runtime)
      if length == 0 {
        object.set("length", .number(0))
        return .undefined
      }
      let first = object.get("0")
      for index in 1..<length {
        if object.hasOwn(String(index)) {
          object.properties[String(index - 1)] = object.get(String(index))
        } else {
          object.properties.removeValue(forKey: String(index - 1))
        }
      }
      object.deleteOwn(String(length - 1))
      object.set("length", .number(Double(length - 1)))
      return first
    }
    proto.defineNative("unshift") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = try arrayLength(object, runtime: runtime)
      let count = args.count
      if count > 0 {
        for index in stride(from: length - 1, through: 0, by: -1) {
          if object.hasOwn(String(index)) {
            object.properties[String(index + count)] = object.get(String(index))
          } else {
            object.properties.removeValue(forKey: String(index + count))
          }
        }
        for (offset, argument) in args.enumerated() {
          object.properties[String(offset)] = argument
        }
      }
      object.set("length", .number(Double(length + count)))
      return .number(Double(length + count))
    }
    proto.defineNative("slice") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = try arrayLength(object, runtime: runtime)
      let start = clampIndex(args.first, length: length, runtime: runtime)
      let end = args.count > 1
        ? clampIndex(args[1], length: length, runtime: runtime) : length
      var values: [JSValue] = []
      if end > start {
        for index in start..<end {
          values.append(object.hasOwn(String(index)) ? object.get(String(index)) : .undefined)
        }
      }
      return .object(runtime.makeArray(values))
    }
    proto.defineNative("splice") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = try arrayLength(object, runtime: runtime)
      let start = clampIndex(args.first, length: length, runtime: runtime)
      let deleteCount: Int
      if args.count > 1 {
        let raw = try runtime.toNumber(args[1])
        deleteCount = raw.isNaN ? 0 : max(0, min(length - start, Int(raw)))
      } else {
        deleteCount = length - start
      }
      var removed: [JSValue] = []
      for index in start..<(start + deleteCount) {
        removed.append(object.hasOwn(String(index)) ? object.get(String(index)) : .undefined)
      }
      let additions = Array(args.dropFirst(2))
      let tail = (start + deleteCount)..<length
      var tailValues: [(Int, JSValue)] = []
      for index in tail where object.hasOwn(String(index)) {
        tailValues.append((index, object.get(String(index))))
      }
      for index in start..<length {
        object.properties.removeValue(forKey: String(index))
      }
      var cursor = start
      for addition in additions {
        object.properties[String(cursor)] = addition
        cursor += 1
      }
      for (oldIndex, value) in tailValues {
        object.properties[String(cursor)] = value
        cursor += 1
        _ = oldIndex
      }
      object.set("length", .number(Double(length - deleteCount + additions.count)))
      return .object(runtime.makeArray(removed))
    }
    proto.defineNative("map") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      guard case .function = args.first ?? .undefined else {
        throw JSError.type("Callback must be callable")
      }
      let callback = args.first ?? .undefined
      let receiver = args.count > 1 ? args[1] : .undefined
      let length = try arrayLength(object, runtime: runtime)
      var values: [JSValue] = []
      for index in 0..<length {
        if object.hasOwn(String(index)) {
          values.append(
            try runtime.callValue(callback, thisValue: receiver,
              arguments: [object.get(String(index)), .number(Double(index)), thisArg]))
        } else {
          values.append(.undefined)
        }
      }
      let result = runtime.makeArray(values)
      for index in 0..<length where !object.hasOwn(String(index)) {
        result.properties.removeValue(forKey: String(index))
      }
      return .object(result)
    }
    proto.defineNative("filter") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      guard case .function = args.first ?? .undefined else {
        throw JSError.type("Callback must be callable")
      }
      let callback = args.first ?? .undefined
      let receiver = args.count > 1 ? args[1] : .undefined
      let length = try arrayLength(object, runtime: runtime)
      var values: [JSValue] = []
      for index in 0..<length where object.hasOwn(String(index)) {
        let value = object.get(String(index))
        if try runtime.callValue(callback, thisValue: receiver,
          arguments: [value, .number(Double(index)), thisArg]).truthy
        {
          values.append(value)
        }
      }
      return .object(runtime.makeArray(values))
    }
    proto.defineNative("forEach") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      guard case .function = args.first ?? .undefined else {
        throw JSError.type("Callback must be callable")
      }
      let callback = args.first ?? .undefined
      let receiver = args.count > 1 ? args[1] : .undefined
      let length = try arrayLength(object, runtime: runtime)
      for index in 0..<length where object.hasOwn(String(index)) {
        _ = try runtime.callValue(callback, thisValue: receiver,
          arguments: [object.get(String(index)), .number(Double(index)), thisArg])
      }
      return .undefined
    }
    proto.defineNative("reduce") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      return try reduceHelper(runtime: runtime, thisArg: thisArg, args: args, right: false)
    }
    proto.defineNative("reduceRight") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      return try reduceHelper(runtime: runtime, thisArg: thisArg, args: args, right: true)
    }
    proto.defineNative("find") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let found = try findHelper(runtime: runtime, thisArg: thisArg, args: args)
      return found ?? .undefined
    }
    proto.defineNative("findIndex") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      guard case .function = args.first ?? .undefined else {
        throw JSError.type("Callback must be callable")
      }
      let callback = args.first ?? .undefined
      let receiver = args.count > 1 ? args[1] : .undefined
      let length = try arrayLength(object, runtime: runtime)
      for index in 0..<length where object.hasOwn(String(index)) {
        if try runtime.callValue(callback, thisValue: receiver,
          arguments: [object.get(String(index)), .number(Double(index)), thisArg]).truthy
        {
          return .number(Double(index))
        }
      }
      return .number(-1)
    }
    proto.defineNative("indexOf") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = try arrayLength(object, runtime: runtime)
      let target = args.first ?? .undefined
      var start = 0
      if args.count > 1 {
        let raw = try runtime.toNumber(args[1])
        start = raw.isNaN ? 0 : max(0, Int(raw))
      }
      for index in start..<length where object.hasOwn(String(index)) {
        if runtime.strictEqual(object.get(String(index)), target) {
          return .number(Double(index))
        }
      }
      return .number(-1)
    }
    proto.defineNative("lastIndexOf") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = try arrayLength(object, runtime: runtime)
      let target = args.first ?? .undefined
      var start = length - 1
      if args.count > 1 {
        let raw = try runtime.toNumber(args[1])
        start = raw.isNaN ? length - 1 : min(length - 1, Int(raw))
      }
      for index in stride(from: start, through: 0, by: -1)
        where object.hasOwn(String(index))
      {
        if runtime.strictEqual(object.get(String(index)), target) {
          return .number(Double(index))
        }
      }
      return .number(-1)
    }
    proto.defineNative("includes") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = try arrayLength(object, runtime: runtime)
      let target = args.first ?? .undefined
      var start = 0
      if args.count > 1 {
        let raw = try runtime.toNumber(args[1])
        start = raw.isNaN ? 0 : max(0, Int(raw))
      }
      for index in start..<length {
        let value: JSValue = object.hasOwn(String(index)) ? object.get(String(index)) : .undefined
        if sameValueZero(value, target, runtime: runtime) { return .bool(true) }
      }
      return .bool(false)
    }
    proto.defineNative("join") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let separator = args.first.map { try? runtime.toString($0) } ?? "," as String?
      let glue = separator ?? ","
      let length = try arrayLength(object, runtime: runtime)
      var parts: [String] = []
      for index in 0..<length {
        let value = object.hasOwn(String(index)) ? object.get(String(index)) : .undefined
        if value.isNullish || (try? runtime.toString(value)) == nil {
          parts.append("")
        } else if case .undefined = value {
          parts.append("")
        } else {
          parts.append(try runtime.toString(value))
        }
      }
      return .string(parts.joined(separator: glue))
    }
    proto.defineNative("toString") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = try arrayLength(object, runtime: runtime)
      var parts: [String] = []
      for index in 0..<length {
        let value = object.hasOwn(String(index)) ? object.get(String(index)) : .undefined
        if case .undefined = value {
          parts.append("")
        } else if case .null = value {
          parts.append("")
        } else {
          parts.append(try runtime.toString(value))
        }
      }
      return .string(parts.joined(separator: ","))
    }
    proto.defineNative("concat") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      var values: [JSValue] = []
      let inputs = [thisArg] + args
      for input in inputs {
        if isJSArray(input, runtime: runtime),
          case .object(let object) = input
        {
          let length = try arrayLength(object, runtime: runtime)
          for index in 0..<length {
            values.append(
              object.hasOwn(String(index)) ? object.get(String(index)) : .undefined)
          }
        } else {
          values.append(input)
        }
      }
      return .object(runtime.makeArray(values))
    }
    proto.defineNative("reverse") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = try arrayLength(object, runtime: runtime)
      var lower = 0
      var upper = length - 1
      while lower < upper {
        let hasLower = object.hasOwn(String(lower))
        let hasUpper = object.hasOwn(String(upper))
        let lowerValue = object.get(String(lower))
        let upperValue = object.get(String(upper))
        if hasUpper {
          object.properties[String(lower)] = upperValue
        } else {
          object.properties.removeValue(forKey: String(lower))
        }
        if hasLower {
          object.properties[String(upper)] = lowerValue
        } else {
          object.properties.removeValue(forKey: String(upper))
        }
        lower += 1
        upper -= 1
      }
      return thisArg
    }
    proto.defineNative("sort") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let comparator = args.first
      let hasComparator = comparator.map { if case .function = $0 { true } else { false } }
        ?? false
      let length = try arrayLength(object, runtime: runtime)
      var present: [JSValue] = []
      var undefinedCount = 0
      for index in 0..<length where object.hasOwn(String(index)) {
        let value = object.get(String(index))
        if case .undefined = value {
          undefinedCount += 1
        } else {
          present.append(value)
        }
      }
      if hasComparator, let comparator {
        var order = present
        for outer in 1..<order.count {
          var inner = outer
          while inner > 0 {
            let raw = try runtime.callValue(
              comparator, thisValue: .undefined, arguments: [order[inner], order[inner - 1]])
            let number = (try? runtime.toNumber(raw)) ?? 0
            if number < 0 {
              order.swapAt(inner, inner - 1)
              inner -= 1
            } else {
              break
            }
          }
        }
        present = order
      } else {
        present.sort {
          let left = (try? runtime.toString($0)) ?? ""
          let right = (try? runtime.toString($1)) ?? ""
          return left < right
        }
      }
      var cursor = 0
      for value in present {
        object.properties[String(cursor)] = value
        cursor += 1
      }
      for _ in 0..<undefinedCount {
        object.properties[String(cursor)] = .undefined
        cursor += 1
      }
      while cursor < length {
        object.properties.removeValue(forKey: String(cursor))
        cursor += 1
      }
      return thisArg
    }
    proto.defineNative("fill") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let value = args.first ?? .undefined
      let length = try arrayLength(object, runtime: runtime)
      let start = clampIndex(args.count > 1 ? args[1] : .undefined, length: length,
        runtime: runtime)
      let end = args.count > 2
        ? clampIndex(args[2], length: length, runtime: runtime) : length
      if end > start {
        for index in start..<end { object.properties[String(index)] = value }
      }
      return thisArg
    }
    proto.defineNative("some") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      guard case .function = args.first ?? .undefined else {
        throw JSError.type("Callback must be callable")
      }
      let callback = args.first ?? .undefined
      let receiver = args.count > 1 ? args[1] : .undefined
      let length = try arrayLength(object, runtime: runtime)
      for index in 0..<length where object.hasOwn(String(index)) {
        if try runtime.callValue(callback, thisValue: receiver,
          arguments: [object.get(String(index)), .number(Double(index)), thisArg]).truthy
        {
          return .bool(true)
        }
      }
      return .bool(false)
    }
    proto.defineNative("every") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      guard case .function = args.first ?? .undefined else {
        throw JSError.type("Callback must be callable")
      }
      let callback = args.first ?? .undefined
      let receiver = args.count > 1 ? args[1] : .undefined
      let length = try arrayLength(object, runtime: runtime)
      for index in 0..<length where object.hasOwn(String(index)) {
        if try runtime.callValue(callback, thisValue: receiver,
          arguments: [object.get(String(index)), .number(Double(index)), thisArg]).truthy
          == false
        {
          return .bool(false)
        }
      }
      return .bool(true)
    }
    proto.defineNative("flat") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      var depth = 1
      if let first = args.first {
        let raw = try runtime.toNumber(first)
        depth = raw.isNaN ? 0 : max(0, Int(raw))
      }
      return .object(runtime.makeArray(try flattenHelper(
        runtime: runtime, value: thisArg, depth: depth)))
    }
    proto.defineNative("copyWithin") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = try arrayLength(object, runtime: runtime)
      let target = clampIndex(args.first, length: length, runtime: runtime)
      let start = args.count > 1
        ? clampIndex(args[1], length: length, runtime: runtime) : 0
      let end = args.count > 2
        ? clampIndex(args[2], length: length, runtime: runtime) : length
      let count = min(end - start, length - target)
      if count <= 0 { return thisArg }
      var block: [JSValue?] = []
      for index in start..<(start + count) {
        block.append(object.hasOwn(String(index)) ? object.get(String(index)) : nil)
      }
      for (offset, value) in block.enumerated() {
        if let value {
          object.properties[String(target + offset)] = value
        } else {
          object.properties.removeValue(forKey: String(target + offset))
        }
      }
      return thisArg
    }
    proto.defineNative("entries") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = (try? arrayLength(object, runtime: runtime)) ?? 0
      var pairs: [JSValue] = []
      for index in 0..<length {
        pairs.append(.object(runtime.makeArray([
          .number(Double(index)),
          object.hasOwn(String(index)) ? object.get(String(index)) : .undefined,
        ])))
      }
      return .object(makeIterator(runtime: runtime, values: pairs, asEntries: true))
    }
    proto.defineNative("keys") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = (try? arrayLength(object, runtime: runtime)) ?? 0
      let values = (0..<length).map { JSValue.number(Double($0)) }
      return .object(makeIterator(runtime: runtime, values: values, asEntries: false))
    }
    proto.defineNative("values") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = (try? arrayLength(object, runtime: runtime)) ?? 0
      var values: [JSValue] = []
      for index in 0..<length {
        values.append(
          object.hasOwn(String(index)) ? object.get(String(index)) : .undefined)
      }
      return .object(makeIterator(runtime: runtime, values: values, asEntries: false))
    }
    proto.defineNative("at") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let length = try arrayLength(object, runtime: runtime)
      let raw = try runtime.toNumber(args.first ?? .undefined)
      if raw.isNaN { return .undefined }
      var index = Int(raw)
      if index < 0 { index += length }
      if index < 0 || index >= length { return .undefined }
      if !object.hasOwn(String(index)) { return .undefined }
      return object.get(String(index))
    }
  }

  static func buildNewArray(runtime: JSRuntime, args: [JSValue]) throws -> JSValue {
    if args.count == 1, case .number(let number) = args[0] {
      guard number >= 0, number.rounded() == number, number < 4294967295 else {
        throw JSError.range("Invalid array length")
      }
      let object = runtime.makeArray([])
      object.set("length", .number(number))
      return .object(object)
    }
    return .object(runtime.makeArray(args))
  }

  static func clampIndex(_ value: JSValue?, length: Int, runtime: JSRuntime) -> Int {
    guard let value, !value.isNullish else { return 0 }
    guard let raw = try? runtime.toNumber(value), !raw.isNaN else { return 0 }
    let index = Int(raw)
    if index < 0 { return max(0, length + index) }
    return min(length, index)
  }

  static func reduceHelper(
    runtime: JSRuntime, thisArg: JSValue, args: [JSValue], right: Bool
  ) throws -> JSValue {
    guard case .object(let object) = thisArg else {
      throw JSError.type("Receiver must be an object")
    }
    guard case .function = args.first ?? .undefined else {
      throw JSError.type("Callback must be callable")
    }
    let callback = args.first ?? .undefined
    let length = try arrayLength(object, runtime: runtime)
    let indices: [Int] = right
      ? stride(from: length - 1, through: 0, by: -1).map { $0 } : Array(0..<length)
    var cursor = indices.makeIterator()
    var accumulator: JSValue
    if args.count > 1 {
      accumulator = args[1]
    } else {
      var seed: JSValue?
      while let index = cursor.next() {
        if object.hasOwn(String(index)) {
          seed = object.get(String(index))
          break
        }
      }
      guard let seed else {
        throw JSError.type("Reduce of empty array with no initial value")
      }
      accumulator = seed
    }
    while let index = cursor.next() {
      if !object.hasOwn(String(index)) { continue }
      accumulator = try runtime.callValue(callback, thisValue: .undefined,
        arguments: [
          accumulator, object.get(String(index)), .number(Double(index)), thisArg,
        ])
    }
    return accumulator
  }

  static func findHelper(
    runtime: JSRuntime, thisArg: JSValue, args: [JSValue]
  ) throws -> JSValue? {
    guard case .object(let object) = thisArg else {
      throw JSError.type("Receiver must be an object")
    }
    guard case .function = args.first ?? .undefined else {
      throw JSError.type("Callback must be callable")
    }
    let callback = args.first ?? .undefined
    let receiver = args.count > 1 ? args[1] : .undefined
    let length = try arrayLength(object, runtime: runtime)
    for index in 0..<length where object.hasOwn(String(index)) {
      let value = object.get(String(index))
      if try runtime.callValue(callback, thisValue: receiver,
        arguments: [value, .number(Double(index)), thisArg]).truthy
      {
        return value
      }
    }
    return nil
  }

  static func flattenHelper(
    runtime: JSRuntime, value: JSValue, depth: Int
  ) throws -> [JSValue] {
    guard depth > 0, isJSArray(value, runtime: runtime),
      case .object(let object) = value
    else {
      return [value]
    }
    var result: [JSValue] = []
    let length = try arrayLength(object, runtime: runtime)
    for index in 0..<length {
      let item: JSValue =
        object.hasOwn(String(index)) ? object.get(String(index)) : .undefined
      if case .undefined = item, !object.hasOwn(String(index)) {
        result.append(.undefined)
      } else {
        result.append(contentsOf: try flattenHelper(
          runtime: runtime, value: item, depth: depth - 1))
      }
    }
    return result
  }

  static func installNumberBoolean(into runtime: JSRuntime) {
    let numberProto = runtime.numberPrototype
    numberProto.defineNative("toString") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let value = try primitiveNumber(thisArg)
      if let first = args.first, !first.isNullish {
        let radix = Int(try runtime.toNumber(first))
        if radix < 2 || radix > 36 {
          throw JSError.range("Radix must be between 2 and 36")
        }
        if radix == 10 { return .string(try runtime.toString(.number(value))) }
        return .string(numberToRadix(value, radix: radix))
      }
      return .string(try runtime.toString(.number(value)))
    }
    numberProto.defineNative("toFixed") { thisArg, args in
      let value = try primitiveNumber(thisArg)
      var digits = 0
      if let first = args.first, !first.isNullish {
        if case .number(let number) = first { digits = Int(number) }
      }
      if digits < 0 || digits > 100 {
        throw JSError.range("toFixed digits must be between 0 and 100")
      }
      if value.isNaN { return .string("NaN") }
      if value.isInfinite { return .string(value > 0 ? "Infinity" : "-Infinity") }
      return .string(String(format: "%.\(digits)f", value))
    }
    numberProto.defineNative("toExponential") { thisArg, args in
      let value = try primitiveNumber(thisArg)
      if value.isNaN { return .string("NaN") }
      if value.isInfinite { return .string(value > 0 ? "Infinity" : "-Infinity") }
      if let first = args.first, !first.isNullish {
        guard case .number(let number) = first, number >= 0, number <= 100 else {
          throw JSError.range("Invalid fraction digits")
        }
        return .string(String(format: "%.\(Int(number))e", value))
      }
      return .string(String(format: "%e", value))
    }
    numberProto.defineNative("toPrecision") { thisArg, args in
      let value = try primitiveNumber(thisArg)
      if value.isNaN { return .string("NaN") }
      if value.isInfinite { return .string(value > 0 ? "Infinity" : "-Infinity") }
      guard let first = args.first, !first.isNullish else {
        return .string(String(value))
      }
      guard case .number(let number) = first, number >= 1, number <= 100 else {
        throw JSError.range("Invalid precision")
      }
      return .string(String(format: "%.\(Int(number))g", value))
    }
    numberProto.defineNative("valueOf") { thisArg, _ in
      .number(try primitiveNumber(thisArg))
    }
    let numberConstructor = makeConstructor(
      runtime: runtime, name: "Number",
      call: { [weak runtime] args in
        guard let runtime else { return .undefined }
        if let first = args.first {
          return .number(try runtime.toNumber(first))
        }
        return .number(0)
      },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        let object = JSObject(prototype: runtime.numberPrototype)
        if let first = args.first {
          object.set("value", .number(try runtime.toNumber(first)))
        } else {
          object.set("value", .number(0))
        }
        return .object(object)
      })
    let numberStatics = numberConstructor.staticProperties
    numberStatics.set("EPSILON", .number(2.220446049250313e-16))
    numberStatics.set("MAX_SAFE_INTEGER", .number(9007199254740991))
    numberStatics.set("MIN_SAFE_INTEGER", .number(-9007199254740991))
    numberStatics.set("MAX_VALUE", .number(Double.greatestFiniteMagnitude))
    numberStatics.set("MIN_VALUE", .number(Double.leastNormalMagnitude))
    numberStatics.set("NaN", .number(.nan))
    numberStatics.set("POSITIVE_INFINITY", .number(.infinity))
    numberStatics.set("NEGATIVE_INFINITY", .number(-.infinity))
    numberStatics.defineNative("isNaN") { _, args in
      if case .number(let number) = args.first { return .bool(number.isNaN) }
      return .bool(false)
    }
    numberStatics.defineNative("isFinite") { _, args in
      if case .number(let number) = args.first { return .bool(number.isFinite) }
      return .bool(false)
    }
    numberStatics.defineNative("isInteger") { _, args in
      if case .number(let number) = args.first {
        return .bool(number.isFinite && number.rounded() == number)
      }
      return .bool(false)
    }
    numberStatics.defineNative("isSafeInteger") { _, args in
      if case .number(let number) = args.first {
        return .bool(number.isFinite && number.rounded() == number && abs(number) <= 9007199254740991)
      }
      return .bool(false)
    }
    numberStatics.defineNative("parseInt") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      let global = runtime.globals.get("parseInt") ?? .undefined
      return try runtime.callValue(global, thisValue: .undefined, arguments: args)
    }
    numberStatics.defineNative("parseFloat") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      let global = runtime.globals.get("parseFloat") ?? .undefined
      return try runtime.callValue(global, thisValue: .undefined, arguments: args)
    }
    publish(into: runtime, "Number", .function(numberConstructor))
    numberConstructor.prototypeObject = runtime.numberPrototype
    runtime.numberPrototype.set("constructor", .function(numberConstructor))
    let booleanProto = runtime.booleanPrototype
    booleanProto.defineNative("toString") { thisArg, _ in
      .string(try primitiveBoolean(thisArg) ? "true" : "false")
    }
    booleanProto.defineNative("valueOf") { thisArg, _ in
      .bool(try primitiveBoolean(thisArg))
    }
    let booleanConstructor = makeConstructor(
      runtime: runtime, name: "Boolean",
      call: { args in .bool(args.first?.truthy ?? false) },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        let object = JSObject(prototype: runtime.booleanPrototype)
        object.set("value", .bool(args.first?.truthy ?? false))
        return .object(object)
      })
    publish(into: runtime, "Boolean", .function(booleanConstructor))
    booleanConstructor.prototypeObject = runtime.booleanPrototype
    runtime.booleanPrototype.set("constructor", .function(booleanConstructor))
  }

  static func primitiveNumber(_ value: JSValue) throws -> Double {
    switch value {
    case .number(let number): return number
    case .object(let object):
      if case .number(let number) = object.get("value") { return number }
      throw JSError.type("Receiver must be a Number")
    default:
      throw JSError.type("Receiver must be a Number")
    }
  }

  static func primitiveBoolean(_ value: JSValue) throws -> Bool {
    switch value {
    case .bool(let flag): return flag
    case .object(let object):
      if case .bool(let flag) = object.get("value") { return flag }
      throw JSError.type("Receiver must be a Boolean")
    default:
      throw JSError.type("Receiver must be a Boolean")
    }
  }

  static func numberToRadix(_ value: Double, radix: Int) -> String {
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value > 0 ? "Infinity" : "-Infinity" }
    let digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    let negative = value < 0
    var integral = UInt64(abs(value).rounded(.towardZero))
    var fraction = abs(value) - Double(integral)
    var text = ""
    repeat {
      let digit = Int(integral % UInt64(radix))
      text = String(digits[digits.index(digits.startIndex, offsetBy: digit)]) + text
      integral /= UInt64(radix)
    } while integral > 0
    if fraction > 0 {
      text += "."
      for _ in 0..<10 {
        fraction *= Double(radix)
        let digit = Int(fraction)
        text += String(digits[digits.index(digits.startIndex, offsetBy: digit)])
        fraction -= Double(digit)
        if fraction == 0 { break }
      }
    }
    return negative ? "-\(text)" : text
  }
}