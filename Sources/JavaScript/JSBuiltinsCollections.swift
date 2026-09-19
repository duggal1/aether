import DOM
import Foundation

extension JSBuiltins {
  static func sameValueZero(_ lhs: JSValue, _ rhs: JSValue, runtime: JSRuntime) -> Bool {
    if case .number(let a) = lhs, case .number(let b) = rhs {
      if a.isNaN && b.isNaN { return true }
      return a == b
    }
    return runtime.strictEqual(lhs, rhs)
  }

  static func makeIterator(
    runtime: JSRuntime, values: [JSValue], asEntries: Bool
  ) -> JSObject {
    let object = JSObject(prototype: runtime.objectPrototype)
    var index = 0
    let next = JSFunction(native: { [weak runtime] _ in
      guard let runtime else { return .undefined }
      let record = JSObject(prototype: runtime.objectPrototype)
      if index >= values.count {
        record.set("done", .bool(true))
        record.set("value", .undefined)
        return .object(record)
      }
      let value = values[index]
      index += 1
      record.set("done", .bool(false))
      if asEntries {
        record.set("value", value)
      } else {
        record.set("value", value)
      }
      return .object(record)
    }, name: "next")
    object.set("next", .function(next))
    return object
  }

  static func installMapSet(into runtime: JSRuntime) {
    let mapProto = runtime.mapPrototype
    mapProto.defineNative("set") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, object.mapEntries != nil else {
        throw JSError.type("Receiver must be a Map")
      }
      let key = args.first ?? .undefined
      let value = args.count > 1 ? args[1] : .undefined
      var entries = object.mapEntries ?? []
      var found = false
      for index in entries.indices {
        if sameValueZero(entries[index].key, key, runtime: runtime) {
          entries[index] = (key: entries[index].key, value: value)
          found = true
          break
        }
      }
      if !found { entries.append((key: key, value: value)) }
      object.mapEntries = entries
      object.set("size", .number(Double(entries.count)))
      return thisArg
    }
    mapProto.defineNative("get") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, let entries = object.mapEntries else {
        throw JSError.type("Receiver must be a Map")
      }
      let key = args.first ?? .undefined
      for entry in entries {
        if sameValueZero(entry.key, key, runtime: runtime) { return entry.value }
      }
      return .undefined
    }
    mapProto.defineNative("has") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, let entries = object.mapEntries else {
        throw JSError.type("Receiver must be a Map")
      }
      let key = args.first ?? .undefined
      for entry in entries {
        if sameValueZero(entry.key, key, runtime: runtime) { return .bool(true) }
      }
      return .bool(false)
    }
    mapProto.defineNative("delete") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, object.mapEntries != nil else {
        throw JSError.type("Receiver must be a Map")
      }
      let key = args.first ?? .undefined
      var entries = object.mapEntries ?? []
      for index in entries.indices {
        if sameValueZero(entries[index].key, key, runtime: runtime) {
          entries.remove(at: index)
          object.mapEntries = entries
          object.set("size", .number(Double(entries.count)))
          return .bool(true)
        }
      }
      return .bool(false)
    }
    mapProto.defineNative("clear") { thisArg, _ in
      guard case .object(let object) = thisArg, object.mapEntries != nil else {
        throw JSError.type("Receiver must be a Map")
      }
      object.mapEntries = []
      object.set("size", .number(0))
      return .undefined
    }
    mapProto.defineNative("forEach") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, let entries = object.mapEntries else {
        throw JSError.type("Receiver must be a Map")
      }
      guard case .function = args.first ?? .undefined else {
        throw JSError.type("Callback must be callable")
      }
      for entry in entries {
        _ = try runtime.callValue(
          args.first ?? .undefined, thisValue: .undefined,
          arguments: [entry.value, entry.key, thisArg])
      }
      return .undefined
    }
    mapProto.defineNative("keys") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, let entries = object.mapEntries else {
        throw JSError.type("Receiver must be a Map")
      }
      return .object(makeIterator(
        runtime: runtime, values: entries.map { $0.key }, asEntries: false))
    }
    mapProto.defineNative("values") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, let entries = object.mapEntries else {
        throw JSError.type("Receiver must be a Map")
      }
      return .object(makeIterator(
        runtime: runtime, values: entries.map { $0.value }, asEntries: false))
    }
    mapProto.defineNative("entries") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, let entries = object.mapEntries else {
        throw JSError.type("Receiver must be a Map")
      }
      let pairs = entries.map { entry in
        JSValue.object(runtime.makeArray([entry.key, entry.value]))
      }
      return .object(makeIterator(runtime: runtime, values: pairs, asEntries: true))
    }
    let mapConstructor = makeConstructor(
      runtime: runtime, name: "Map",
      call: { _ in throw JSError.type("Map must be constructed") },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        let object = JSObject(prototype: runtime.mapPrototype)
        object.mapEntries = []
        object.set("size", .number(0))
        if let first = args.first, !first.isNullish {
          guard let items = try runtime.iterateValues(first) else {
            throw JSError.type("Argument is not iterable")
          }
          var entries: [(key: JSValue, value: JSValue)] = []
          for item in items {
            guard let pair = try runtime.iterateValues(item), pair.count >= 2 else {
              throw JSError.type("Entry must be iterable")
            }
            entries.append((key: pair[0], value: pair[1]))
          }
          object.mapEntries = entries
          object.set("size", .number(Double(entries.count)))
        }
        return .object(object)
      })
    publish(into: runtime, "Map", .function(mapConstructor))
    mapConstructor.prototypeObject = runtime.mapPrototype
    runtime.mapPrototype.set("constructor", .function(mapConstructor))

    let setProto = runtime.setPrototype
    setProto.defineNative("add") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, object.setValues != nil else {
        throw JSError.type("Receiver must be a Set")
      }
      let value = args.first ?? .undefined
      var values = object.setValues ?? []
      if !values.contains(where: { sameValueZero($0, value, runtime: runtime) }) {
        values.append(value)
      }
      object.setValues = values
      object.set("size", .number(Double(values.count)))
      return thisArg
    }
    setProto.defineNative("has") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, let values = object.setValues else {
        throw JSError.type("Receiver must be a Set")
      }
      let key = args.first ?? .undefined
      return .bool(values.contains(where: { sameValueZero($0, key, runtime: runtime) }))
    }
    setProto.defineNative("delete") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, object.setValues != nil else {
        throw JSError.type("Receiver must be a Set")
      }
      let key = args.first ?? .undefined
      var values = object.setValues ?? []
      if let index = values.firstIndex(where: { sameValueZero($0, key, runtime: runtime) }) {
        values.remove(at: index)
        object.setValues = values
        object.set("size", .number(Double(values.count)))
        return .bool(true)
      }
      return .bool(false)
    }
    setProto.defineNative("clear") { thisArg, _ in
      guard case .object(let object) = thisArg, object.setValues != nil else {
        throw JSError.type("Receiver must be a Set")
      }
      object.setValues = []
      object.set("size", .number(0))
      return .undefined
    }
    setProto.defineNative("forEach") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, let values = object.setValues else {
        throw JSError.type("Receiver must be a Set")
      }
      guard case .function = args.first ?? .undefined else {
        throw JSError.type("Callback must be callable")
      }
      for value in values {
        _ = try runtime.callValue(
          args.first ?? .undefined, thisValue: .undefined,
          arguments: [value, value, thisArg])
      }
      return .undefined
    }
    setProto.defineNative("values") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, let values = object.setValues else {
        throw JSError.type("Receiver must be a Set")
      }
      return .object(makeIterator(runtime: runtime, values: values, asEntries: false))
    }
    setProto.defineNative("keys") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, let values = object.setValues else {
        throw JSError.type("Receiver must be a Set")
      }
      return .object(makeIterator(runtime: runtime, values: values, asEntries: false))
    }
    setProto.defineNative("entries") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, let values = object.setValues else {
        throw JSError.type("Receiver must be a Set")
      }
      let pairs = values.map { value in
        JSValue.object(runtime.makeArray([value, value]))
      }
      return .object(makeIterator(runtime: runtime, values: pairs, asEntries: true))
    }
    let setConstructor = makeConstructor(
      runtime: runtime, name: "Set",
      call: { _ in throw JSError.type("Set must be constructed") },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        let object = JSObject(prototype: runtime.setPrototype)
        object.setValues = []
        object.set("size", .number(0))
        if let first = args.first, !first.isNullish {
          guard let items = try runtime.iterateValues(first) else {
            throw JSError.type("Argument is not iterable")
          }
          var values: [JSValue] = []
          for item in items {
            if !values.contains(where: { sameValueZero($0, item, runtime: runtime) }) {
              values.append(item)
            }
          }
          object.setValues = values
          object.set("size", .number(Double(values.count)))
        }
        return .object(object)
      })
    publish(into: runtime, "Set", .function(setConstructor))
    setConstructor.prototypeObject = runtime.setPrototype
    runtime.setPrototype.set("constructor", .function(setConstructor))
    installWeakCollections(into: runtime)
  }

  static func installWeakCollections(into runtime: JSRuntime) {
    let weakMapProto = JSObject(prototype: runtime.objectPrototype)
    let weakSetProto = JSObject(prototype: runtime.objectPrototype)
    weakMapProto.defineNative("set") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let table) = thisArg,
        case .object(let key) = args.first ?? .undefined
      else {
        throw JSError.type("WeakMap key must be an object")
      }
      let value = args.count > 1 ? args[1] : .undefined
      var entries = table.mapEntries ?? []
      let id = ObjectIdentifier(key)
      var found = false
      for index in entries.indices {
        if case .object(let stored) = entries[index].key, stored === key {
          entries[index] = (key: entries[index].key, value: value)
          found = true
          break
        }
      }
      if !found { entries.append((key: .object(key), value: value)) }
      _ = id
      table.mapEntries = entries
      return thisArg
    }
    weakMapProto.defineNative("get") { thisArg, args in
      guard case .object(let table) = thisArg,
        case .object(let key) = args.first ?? .undefined
      else {
        return .undefined
      }
      for entry in table.mapEntries ?? [] {
        if case .object(let stored) = entry.key, stored === key { return entry.value }
      }
      return .undefined
    }
    weakMapProto.defineNative("has") { thisArg, args in
      guard case .object(let table) = thisArg,
        case .object(let key) = args.first ?? .undefined
      else {
        return .bool(false)
      }
      for entry in table.mapEntries ?? [] {
        if case .object(let stored) = entry.key, stored === key { return .bool(true) }
      }
      return .bool(false)
    }
    weakMapProto.defineNative("delete") { thisArg, args in
      guard case .object(let table) = thisArg,
        case .object(let key) = args.first ?? .undefined
      else {
        return .bool(false)
      }
      var entries = table.mapEntries ?? []
      for index in entries.indices {
        if case .object(let stored) = entries[index].key, stored === key {
          entries.remove(at: index)
          table.mapEntries = entries
          return .bool(true)
        }
      }
      return .bool(false)
    }
    let weakMapConstructor = makeConstructor(
      runtime: runtime, name: "WeakMap",
      call: { _ in throw JSError.type("WeakMap must be constructed") },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        let object = JSObject(prototype: weakMapProto)
        object.mapEntries = []
        if let first = args.first, !first.isNullish {
          guard let items = try runtime.iterateValues(first) else {
            throw JSError.type("Argument is not iterable")
          }
          var entries: [(key: JSValue, value: JSValue)] = []
          for item in items {
            guard let pair = try runtime.iterateValues(item), pair.count >= 2 else {
              throw JSError.type("Entry must be iterable")
            }
            entries.append((key: pair[0], value: pair[1]))
          }
          object.mapEntries = entries
        }
        return .object(object)
      })
    publish(into: runtime, "WeakMap", .function(weakMapConstructor))
    weakSetProto.defineNative("add") { thisArg, args in
      guard case .object(let table) = thisArg,
        case .object(let key) = args.first ?? .undefined
      else {
        throw JSError.type("WeakSet value must be an object")
      }
      var values = table.setValues ?? []
      if !values.contains(where: {
        if case .object(let stored) = $0 { return stored === key }
        return false
      }) {
        values.append(.object(key))
      }
      table.setValues = values
      return thisArg
    }
    weakSetProto.defineNative("has") { thisArg, args in
      guard case .object(let table) = thisArg,
        case .object(let key) = args.first ?? .undefined
      else {
        return .bool(false)
      }
      for value in table.setValues ?? [] {
        if case .object(let stored) = value, stored === key { return .bool(true) }
      }
      return .bool(false)
    }
    weakSetProto.defineNative("delete") { thisArg, args in
      guard case .object(let table) = thisArg,
        case .object(let key) = args.first ?? .undefined
      else {
        return .bool(false)
      }
      var values = table.setValues ?? []
      for index in values.indices {
        if case .object(let stored) = values[index], stored === key {
          values.remove(at: index)
          table.setValues = values
          return .bool(true)
        }
      }
      return .bool(false)
    }
    let weakSetConstructor = makeConstructor(
      runtime: runtime, name: "WeakSet",
      call: { _ in throw JSError.type("WeakSet must be constructed") },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        let object = JSObject(prototype: weakSetProto)
        object.setValues = []
        if let first = args.first, !first.isNullish {
          guard let items = try runtime.iterateValues(first) else {
            throw JSError.type("Argument is not iterable")
          }
          object.setValues = items
        }
        return .object(object)
      })
    publish(into: runtime, "WeakSet", .function(weakSetConstructor))
  }

  static func installDate(into runtime: JSRuntime) {
    let proto = runtime.datePrototype
    func milliseconds(_ value: JSValue) -> Double? {
      if case .object(let object) = value {
        if case .number(let number) = object.get("time") { return number }
      }
      return nil
    }
    proto.defineNative("getTime") { thisArg, _ in
      guard let time = milliseconds(thisArg) else {
        throw JSError.type("Receiver must be a Date")
      }
      return .number(time)
    }
    proto.defineNative("valueOf") { thisArg, _ in
      guard let time = milliseconds(thisArg) else {
        throw JSError.type("Receiver must be a Date")
      }
      return .number(time)
    }
    proto.defineNative("toISOString") { thisArg, _ in
      guard let time = milliseconds(thisArg) else {
        throw JSError.type("Receiver must be a Date")
      }
      let date = Date(timeIntervalSince1970: time / 1000)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return .string(formatter.string(from: date))
    }
    proto.defineNative("toString") { thisArg, _ in
      guard let time = milliseconds(thisArg) else {
        throw JSError.type("Receiver must be a Date")
      }
      let date = Date(timeIntervalSince1970: time / 1000)
      return .string(date.description)
    }
    proto.defineNative("toDateString") { thisArg, _ in
      guard let time = milliseconds(thisArg) else {
        throw JSError.type("Receiver must be a Date")
      }
      let date = Date(timeIntervalSince1970: time / 1000)
      let formatter = DateFormatter()
      formatter.dateStyle = .medium
      formatter.timeStyle = .none
      return .string(formatter.string(from: date))
    }
    let components: [(String, Calendar.Component, Bool)] = [
      ("getFullYear", .year, false), ("getMonth", .month, false),
      ("getDate", .day, false), ("getDay", .weekday, false),
      ("getHours", .hour, false), ("getMinutes", .minute, false),
      ("getSeconds", .second, false),
      ("getUTCFullYear", .year, true), ("getUTCMonth", .month, true),
      ("getUTCDate", .day, true), ("getUTCDay", .weekday, true),
      ("getUTCHours", .hour, true), ("getUTCMinutes", .minute, true),
      ("getUTCSeconds", .second, true),
    ]
    for (name, component, utc) in components {
      proto.defineNative(name) { thisArg, _ in
        guard let time = milliseconds(thisArg) else {
          throw JSError.type("Receiver must be a Date")
        }
        var calendar = Calendar(identifier: .gregorian)
        if utc { calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone }
        let date = Date(timeIntervalSince1970: time / 1000)
        var value = calendar.component(component, from: date)
        if component == .month { value -= 1 }
        if component == .weekday { value -= 1 }
        return .number(Double(value))
      }
    }
    proto.defineNative("getMilliseconds") { thisArg, _ in
      guard let time = milliseconds(thisArg) else {
        throw JSError.type("Receiver must be a Date")
      }
      let fraction = time.truncatingRemainder(dividingBy: 1000)
      return .number(fraction < 0 ? fraction + 1000 : fraction)
    }
    proto.defineNative("setTime") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg,
        object.prototype === runtime.datePrototype
      else {
        throw JSError.type("Receiver must be a Date")
      }
      if case .number(let number) = args.first {
        object.set("time", .number(number))
        return .number(number)
      }
      return .number(.nan)
    }
    let constructor = makeConstructor(
      runtime: runtime, name: "Date",
      call: { _ in .string(Date().description) },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        let object = JSObject(prototype: runtime.datePrototype)
        if args.isEmpty {
          object.set("time", .number(Date().timeIntervalSince1970 * 1000))
        } else if args.count == 1 {
          let first = args[0]
          if case .string(let text) = first {
            object.set("time", .number(parseDateString(text)))
          } else if case .object(let source) = first,
            case .number(let number) = source.get("time")
          {
            object.set("time", .number(number))
          } else {
            object.set("time", .number((try? runtime.toNumber(first)) ?? .nan))
          }
        } else {
          var numbers: [Double] = []
          for argument in args {
            numbers.append((try? runtime.toNumber(argument)) ?? .nan)
          }
          var calendar = Calendar(identifier: .gregorian)
          calendar.timeZone = TimeZone.current
          var parts = DateComponents()
          parts.year = Int(numbers[0])
          parts.month = (numbers.count > 1 ? Int(numbers[1]) : 0) + 1
          parts.day = numbers.count > 2 ? Int(numbers[2]) : 1
          parts.hour = numbers.count > 3 ? Int(numbers[3]) : 0
          parts.minute = numbers.count > 4 ? Int(numbers[4]) : 0
          parts.second = numbers.count > 5 ? Int(numbers[5]) : 0
          if let date = calendar.date(from: parts) {
            object.set("time", .number(date.timeIntervalSince1970 * 1000))
          } else {
            object.set("time", .number(.nan))
          }
        }
        return .object(object)
      })
    let statics = constructor.staticProperties
    statics.defineNative("now") { _, _ in
      .number(Date().timeIntervalSince1970 * 1000)
    }
    statics.defineNative("parse") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      return .number(parseDateString(try runtime.toString(args.first ?? .undefined)))
    }
    statics.defineNative("UTC") { _, args in
      var numbers: [Double] = []
      for argument in args {
        if case .number(let number) = argument { numbers.append(number) }
        else { numbers.append(.nan) }
      }
      guard !numbers.isEmpty, numbers.allSatisfy({ !$0.isNaN }) else {
        return .number(.nan)
      }
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
      var parts = DateComponents()
      parts.year = Int(numbers[0])
      parts.month = (numbers.count > 1 ? Int(numbers[1]) : 0) + 1
      parts.day = numbers.count > 2 ? Int(numbers[2]) : 1
      parts.hour = numbers.count > 3 ? Int(numbers[3]) : 0
      parts.minute = numbers.count > 4 ? Int(numbers[4]) : 0
      parts.second = numbers.count > 5 ? Int(numbers[5]) : 0
      if let date = calendar.date(from: parts) {
        return .number(date.timeIntervalSince1970 * 1000)
      }
      return .number(.nan)
    }
    publish(into: runtime, "Date", .function(constructor))
    constructor.prototypeObject = runtime.datePrototype
    runtime.datePrototype.set("constructor", .function(constructor))
  }

  static func parseDateString(_ text: String) -> Double {
    let formatter = ISO8601DateFormatter()
    for options: ISO8601DateFormatter.Options in [
      [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime],
      [.withFullDate],
    ] {
      formatter.formatOptions = options
      if let date = formatter.date(from: text) {
        return date.timeIntervalSince1970 * 1000
      }
    }
    let fallback = DateFormatter()
    fallback.locale = Locale(identifier: "en_US_POSIX")
    for format in [
      "EEE MMM dd yyyy HH:mm:ss 'GMT'Z", "EEE, dd MMM yyyy HH:mm:ss zzz",
      "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "MM/dd/yyyy",
    ] {
      fallback.dateFormat = format
      if let date = fallback.date(from: text) {
        return date.timeIntervalSince1970 * 1000
      }
    }
    return .nan
  }
}
