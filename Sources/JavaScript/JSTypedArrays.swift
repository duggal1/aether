import DOM
import Foundation

extension JSBuiltins {
  static func installTypedArrays(into runtime: JSRuntime) {
    installArrayBuffer(into: runtime)
    for kind in typedArrayKinds {
      installTypedArrayConstructor(kind: kind, into: runtime)
    }
    installDataViewConstructor(into: runtime)
  }

  static var typedArrayKinds: [String] {
    [
      "int8", "uint8", "uint8clamped", "int16", "uint16", "int32", "uint32", "float32",
      "float64", "bigint64", "biguint64",
    ]
  }

  static func constructorName(for kind: String) -> String {
    switch kind {
    case "int8": return "Int8Array"
    case "uint8": return "Uint8Array"
    case "uint8clamped": return "Uint8ClampedArray"
    case "int16": return "Int16Array"
    case "uint16": return "Uint16Array"
    case "int32": return "Int32Array"
    case "uint32": return "Uint32Array"
    case "float32": return "Float32Array"
    case "float64": return "Float64Array"
    case "bigint64": return "BigInt64Array"
    case "biguint64": return "BigUint64Array"
    case "dataview": return "DataView"
    default: return kind
    }
  }

  static func typedToInteger(_ runtime: JSRuntime, _ value: JSValue) throws -> Int {
    let number = try runtime.toNumber(value)
    if number.isNaN || number == 0 { return 0 }
    if number.isInfinite { return number > 0 ? Int.max / 2 : Int.min / 2 }
    return Int(number.truncatingRemainder(dividingBy: 9007199254740991))
  }

  static func installArrayBuffer(into runtime: JSRuntime) {
    let proto = runtime.arrayBufferPrototype
    runtime.defineAccessor(
      proto, "byteLength",
      getter: JSFunction(nativeMethod: { thisValue, _ in
        guard case .object(let object) = thisValue, object.isArrayBuffer else {
          return .undefined
        }
        return .number(Double(object.arrayBufferData?.count ?? 0))
      }, name: "get byteLength"), setter: nil, enumerable: false, configurable: true)
    proto.defineNative("slice") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg, object.isArrayBuffer else {
        throw JSError.type("ArrayBuffer method requires an ArrayBuffer receiver")
      }
      let bytes = object.arrayBufferData ?? Data()
      let start = args.first.flatMap { try? typedToInteger(runtime, $0) } ?? 0
      let end = args.dropFirst().first.flatMap { try? typedToInteger(runtime, $0) } ?? bytes.count
      let from = start < 0 ? max(0, bytes.count + start) : min(start, bytes.count)
      let to = end < 0 ? max(0, bytes.count + end) : min(end, bytes.count)
      let copy = JSObject(prototype: runtime.arrayBufferPrototype)
      copy.isArrayBuffer = true
      copy.arrayBufferData = from < to ? bytes.subdata(in: from..<to) : Data()
      return .object(copy)
    }

    let ctor = makeConstructor(
      runtime: runtime, name: "ArrayBuffer",
      call: { _ in throw JSError.type("ArrayBuffer requires 'new'") },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        let length = args.first.flatMap { try? typedToInteger(runtime, $0) } ?? 0
        guard length >= 0 else { throw JSError.range("Invalid ArrayBuffer length") }
        let object = JSObject(prototype: runtime.arrayBufferPrototype)
        object.isArrayBuffer = true
        object.arrayBufferData = Data(count: length)
        return .object(object)
      })
    ctor.prototypeObject = runtime.arrayBufferPrototype
    ctor.staticProperties.defineNative("isView") { _, args in
      guard case .object(let object) = args.first else { return .bool(false) }
      return .bool(object.typedArrayKind != nil)
    }
    publish(into: runtime, "ArrayBuffer", .function(ctor))
  }

  static func installTypedArrayConstructor(kind: String, into runtime: JSRuntime) {
    let name = constructorName(for: kind)
    let proto = JSObject(prototype: runtime.typedArrayPrototype)
    proto.set("BYTES_PER_ELEMENT", .number(Double(elementBytes(kind: kind))))
    defineTypedArrayAccessors(proto: proto, runtime: runtime)
    defineTypedArrayMethods(proto: proto, runtime: runtime)
    runtime.typedArrayKindPrototypes[kind] = proto

    let ctor = makeConstructor(
      runtime: runtime, name: name,
      call: { _ in throw JSError.type("\(name) requires 'new'") },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        return try constructTypedArray(runtime: runtime, kind: kind, proto: proto, args: args)
      })
    ctor.prototypeObject = proto
    proto.set("constructor", .function(ctor))
    ctor.staticProperties.set("BYTES_PER_ELEMENT", .number(Double(elementBytes(kind: kind))))
    ctor.staticProperties.defineNative("from") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard let items = try runtime.iterateValues(args.first ?? .undefined) else {
        throw JSError.type("\(name).from requires an iterable")
      }
      var values = items
      if args.count > 1, case .function(let mapper) = args[1] {
        values = try values.enumerated().map { index, value in
          try runtime.callFunction(mapper, arguments: [value, .number(Double(index))])
        }
      }
      return .object(freshTypedArray(runtime: runtime, kind: kind, proto: proto, values: values))
    }
    ctor.staticProperties.defineNative("of") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      return .object(freshTypedArray(runtime: runtime, kind: kind, proto: proto, values: args))
    }
    publish(into: runtime, name, .function(ctor))
  }

  static func defineTypedArrayAccessors(proto: JSObject, runtime: JSRuntime) {
    runtime.defineAccessor(
      proto, "length",
      getter: JSFunction(nativeMethod: { thisValue, _ in
        guard case .object(let object) = thisValue, object.typedArrayKind != nil else {
          return .undefined
        }
        return .number(Double(object.typedArrayLength))
      }, name: "get length"), setter: nil, enumerable: false, configurable: true)
    runtime.defineAccessor(
      proto, "byteLength",
      getter: JSFunction(nativeMethod: { thisValue, _ in
        guard case .object(let object) = thisValue, let kind = object.typedArrayKind else {
          return .undefined
        }
        return .number(Double(object.typedArrayLength * elementBytes(kind: kind)))
      }, name: "get byteLength"), setter: nil, enumerable: false, configurable: true)
    runtime.defineAccessor(
      proto, "byteOffset",
      getter: JSFunction(nativeMethod: { thisValue, _ in
        guard case .object(let object) = thisValue, object.typedArrayKind != nil else {
          return .undefined
        }
        return .number(Double(object.typedArrayOffset))
      }, name: "get byteOffset"), setter: nil, enumerable: false, configurable: true)
    runtime.defineAccessor(
      proto, "buffer",
      getter: JSFunction(nativeMethod: { thisValue, _ in
        guard case .object(let object) = thisValue,
          let buffer = object.typedArrayBuffer
        else { return .undefined }
        return .object(buffer)
      }, name: "get buffer"), setter: nil, enumerable: false, configurable: true)
  }

  static func constructTypedArray(
    runtime: JSRuntime, kind: String, proto: JSObject, args: [JSValue]
  ) throws -> JSValue {
    if let first = args.first, case .object(let other) = first, other.isArrayBuffer {
      let bytes = other.arrayBufferData ?? Data()
      let offset = args.dropFirst().first.flatMap { try? typedToInteger(runtime, $0) } ?? 0
      let stride = elementBytes(kind: kind)
      guard offset >= 0, offset % stride == 0 else {
        throw JSError.range("Invalid typed array offset")
      }
      let count: Int
      if let third = args.dropFirst(2).first, !third.isNullish {
        count = (try? typedToInteger(runtime, third)) ?? 0
      } else {
        guard (bytes.count - offset) % stride == 0 else {
          throw JSError.range("Invalid typed array length")
        }
        count = max(0, (bytes.count - offset) / stride)
      }
      guard count >= 0, offset + count * stride <= bytes.count else {
        throw JSError.range("Invalid typed array length")
      }
      let object = JSObject(prototype: proto)
      attachTypedArray(
        runtime: runtime, object: object, kind: kind, buffer: other, offset: offset, count: count)
      return .object(object)
    }
    if let first = args.first, !first.isNullish,
      let items = try runtime.iterateValues(first)
    {
      return .object(freshTypedArray(runtime: runtime, kind: kind, proto: proto, values: items))
    }
    let count = args.first.flatMap { try? typedToInteger(runtime, $0) } ?? 0
    guard count >= 0 else { throw JSError.range("Invalid typed array length") }
    return .object(
      freshTypedArray(
        runtime: runtime, kind: kind, proto: proto,
        values: Array(repeating: .undefined, count: count)))
  }

  static func freshTypedArray(
    runtime: JSRuntime, kind: String, proto: JSObject, values: [JSValue]
  ) -> JSObject {
    let buffer = JSObject(prototype: runtime.arrayBufferPrototype)
    buffer.isArrayBuffer = true
    buffer.arrayBufferData = Data(count: values.count * elementBytes(kind: kind))
    let object = JSObject(prototype: proto)
    attachTypedArray(
      runtime: runtime, object: object, kind: kind, buffer: buffer, offset: 0,
      count: values.count)
    for (index, value) in values.enumerated() {
      try? writeTypedElement(runtime: runtime, view: object, index: index, value: value)
    }
    return object
  }

  static func attachTypedArray(
    runtime: JSRuntime, object: JSObject, kind: String, buffer: JSObject, offset: Int,
    count: Int
  ) {
    object.typedArrayKind = kind
    object.typedArrayOffset = offset
    object.typedArrayLength = count
    object.typedArrayBuffer = buffer
    object.nativeGet = { [weak object] key in
      guard let object, object.typedArrayKind != nil,
        let index = Int(key), index >= 0, index < object.typedArrayLength
      else { return nil }
      return readTypedElement(runtime: runtime, view: object, index: index)
    }
    object.nativeSet = { [weak object] key, value in
      guard let object, object.typedArrayKind != nil, object.typedArrayKind != "dataview",
        let index = Int(key), index >= 0, index < object.typedArrayLength
      else { return false }
      try? writeTypedElement(runtime: runtime, view: object, index: index, value: value)
      return true
    }
    runtime.defineDataProperty(
      object, "length", .number(Double(count)), writable: false, enumerable: false,
      configurable: false)
  }

  static func defineTypedArrayMethods(proto: JSObject, runtime: JSRuntime) {
    func each(
      _ name: String,
      _ body: @escaping (JSRuntime, JSObject, [JSValue]) throws -> JSValue
    ) {
      proto.defineNative(name) { [weak runtime] thisArg, args in
        guard let runtime else { return .undefined }
        guard case .object(let object) = thisArg, object.typedArrayKind != nil else {
          throw JSError.type("Typed array method requires a typed array receiver")
        }
        return try body(runtime, object, args)
      }
    }
    each("set") { runtime, object, args in
      guard let source = args.first else { return .undefined }
      let offset = args.dropFirst().first.flatMap { try? typedToInteger(runtime, $0) } ?? 0
      guard offset >= 0 else { throw JSError.range("Invalid typed array offset") }
      let items = (try? runtime.iterateValues(source)) ?? []
      guard offset + items.count <= object.typedArrayLength else {
        throw JSError.range("Typed array set out of bounds")
      }
      for (index, item) in items.enumerated() {
        try writeTypedElement(runtime: runtime, view: object, index: offset + index, value: item)
      }
      return .undefined
    }
    each("subarray") { runtime, object, args in
      let count = object.typedArrayLength
      let start = args.first.flatMap { try? typedToInteger(runtime, $0) } ?? 0
      let end = args.dropFirst().first.flatMap { try? typedToInteger(runtime, $0) } ?? count
      let from = start < 0 ? max(0, count + start) : min(start, count)
      let to = end < 0 ? max(0, count + end) : min(end, count)
      let stride = elementBytes(kind: object.typedArrayKind ?? "uint8")
      let view = JSObject(prototype: object.prototype ?? runtime.typedArrayPrototype)
      attachTypedArray(
        runtime: runtime, object: view, kind: object.typedArrayKind ?? "uint8",
        buffer: object.typedArrayBuffer ?? JSObject(),
        offset: object.typedArrayOffset + min(from, to) * stride,
        count: max(0, to - from))
      return .object(view)
    }
    each("slice") { runtime, object, args in
      let count = object.typedArrayLength
      let start = args.first.flatMap { try? typedToInteger(runtime, $0) } ?? 0
      let end = args.dropFirst().first.flatMap { try? typedToInteger(runtime, $0) } ?? count
      let from = start < 0 ? max(0, count + start) : min(start, count)
      let to = end < 0 ? max(0, count + end) : min(end, count)
      var values: [JSValue] = []
      for index in min(from, to)..<max(from, to) {
        values.append(readTypedElement(runtime: runtime, view: object, index: index))
      }
      return .object(
        freshTypedArray(
          runtime: runtime, kind: object.typedArrayKind ?? "uint8",
          proto: object.prototype ?? runtime.typedArrayPrototype, values: values))
    }
    each("fill") { runtime, object, args in
      let value = args.first ?? .undefined
      let start = args.dropFirst().first.flatMap { try? typedToInteger(runtime, $0) } ?? 0
      let end = args.dropFirst(2).first.flatMap { try? typedToInteger(runtime, $0) }
        ?? object.typedArrayLength
      let from = start < 0
        ? max(0, object.typedArrayLength + start) : min(start, object.typedArrayLength)
      let to = end < 0
        ? max(0, object.typedArrayLength + end) : min(end, object.typedArrayLength)
      if to > from {
        for index in from..<to {
          try writeTypedElement(runtime: runtime, view: object, index: index, value: value)
        }
      }
      return .object(object)
    }
    each("join") { runtime, object, args in
      let separator = args.first.map { (try? runtime.toString($0)) ?? "," } ?? ","
      var parts: [String] = []
      for index in 0..<object.typedArrayLength {
        parts.append(
          (try? runtime.toString(readTypedElement(runtime: runtime, view: object, index: index)))
            ?? "")
      }
      return .string(parts.joined(separator: separator))
    }
    each("indexOf") { runtime, object, args in
      let target = args.first ?? .undefined
      for index in 0..<object.typedArrayLength {
        if runtime.strictEqual(
          readTypedElement(runtime: runtime, view: object, index: index), target)
        {
          return .number(Double(index))
        }
      }
      return .number(-1)
    }
    each("includes") { runtime, object, args in
      let target = args.first ?? .undefined
      for index in 0..<object.typedArrayLength {
        if sameValueZero(
          readTypedElement(runtime: runtime, view: object, index: index), target,
          runtime: runtime)
        {
          return .bool(true)
        }
      }
      return .bool(false)
    }
    each("at") { runtime, object, args in
      var index = args.first.flatMap { try? typedToInteger(runtime, $0) } ?? 0
      if index < 0 { index = object.typedArrayLength + index }
      guard index >= 0, index < object.typedArrayLength else { return .undefined }
      return readTypedElement(runtime: runtime, view: object, index: index)
    }
    each("forEach") { runtime, object, args in
      guard case .function(let callback) = args.first else {
        throw JSError.type("Callback must be callable")
      }
      for index in 0..<object.typedArrayLength {
        _ = try runtime.callFunction(
          callback,
          arguments: [
            readTypedElement(runtime: runtime, view: object, index: index),
            .number(Double(index)), .object(object),
          ])
      }
      return .undefined
    }
    each("map") { runtime, object, args in
      guard case .function(let callback) = args.first else {
        throw JSError.type("Callback must be callable")
      }
      var values: [JSValue] = []
      for index in 0..<object.typedArrayLength {
        values.append(
          try runtime.callFunction(
            callback,
            arguments: [
              readTypedElement(runtime: runtime, view: object, index: index),
              .number(Double(index)), .object(object),
            ]))
      }
      return .object(
        freshTypedArray(
          runtime: runtime, kind: object.typedArrayKind ?? "uint8",
          proto: object.prototype ?? runtime.typedArrayPrototype, values: values))
    }
    each("filter") { runtime, object, args in
      guard case .function(let callback) = args.first else {
        throw JSError.type("Callback must be callable")
      }
      var values: [JSValue] = []
      for index in 0..<object.typedArrayLength {
        let value = readTypedElement(runtime: runtime, view: object, index: index)
        let keep = try runtime.callFunction(
          callback, arguments: [value, .number(Double(index)), .object(object)])
        if keep.truthy { values.append(value) }
      }
      return .object(
        freshTypedArray(
          runtime: runtime, kind: object.typedArrayKind ?? "uint8",
          proto: object.prototype ?? runtime.typedArrayPrototype, values: values))
    }
    each("reduce") { runtime, object, args in
      guard case .function(let callback) = args.first else {
        throw JSError.type("Callback must be callable")
      }
      var index = 0
      var accumulator: JSValue
      if args.count > 1 {
        accumulator = args[1]
      } else {
        guard object.typedArrayLength > 0 else {
          throw JSError.type("Reduce of empty typed array")
        }
        accumulator = readTypedElement(runtime: runtime, view: object, index: 0)
        index = 1
      }
      while index < object.typedArrayLength {
        accumulator = try runtime.callFunction(
          callback,
          arguments: [
            accumulator, readTypedElement(runtime: runtime, view: object, index: index),
            .number(Double(index)), .object(object),
          ])
        index += 1
      }
      return accumulator
    }
    each("every") { runtime, object, args in
      guard case .function(let callback) = args.first else {
        throw JSError.type("Callback must be callable")
      }
      for index in 0..<object.typedArrayLength {
        let ok = try runtime.callFunction(
          callback,
          arguments: [
            readTypedElement(runtime: runtime, view: object, index: index),
            .number(Double(index)), .object(object),
          ])
        if !ok.truthy { return .bool(false) }
      }
      return .bool(true)
    }
    each("some") { runtime, object, args in
      guard case .function(let callback) = args.first else {
        throw JSError.type("Callback must be callable")
      }
      for index in 0..<object.typedArrayLength {
        let ok = try runtime.callFunction(
          callback,
          arguments: [
            readTypedElement(runtime: runtime, view: object, index: index),
            .number(Double(index)), .object(object),
          ])
        if ok.truthy { return .bool(true) }
      }
      return .bool(false)
    }
    each("find") { runtime, object, args in
      guard case .function(let callback) = args.first else {
        throw JSError.type("Callback must be callable")
      }
      for index in 0..<object.typedArrayLength {
        let value = readTypedElement(runtime: runtime, view: object, index: index)
        let found = try runtime.callFunction(
          callback, arguments: [value, .number(Double(index)), .object(object)])
        if found.truthy { return value }
      }
      return .undefined
    }
    each("findIndex") { runtime, object, args in
      guard case .function(let callback) = args.first else {
        throw JSError.type("Callback must be callable")
      }
      for index in 0..<object.typedArrayLength {
        let value = readTypedElement(runtime: runtime, view: object, index: index)
        let found = try runtime.callFunction(
          callback, arguments: [value, .number(Double(index)), .object(object)])
        if found.truthy { return .number(Double(index)) }
      }
      return .number(-1)
    }
    each("sort") { runtime, object, args in
      var values = (0..<object.typedArrayLength).map {
        readTypedElement(runtime: runtime, view: object, index: $0)
      }
      if case .function(let comparator) = args.first {
        var order = Array(0..<values.count)
        order.sort { a, b in
          let result =
            (try? runtime.callFunction(comparator, arguments: [values[a], values[b]]))
            .flatMap { try? runtime.toNumber($0) } ?? 0
          return result < 0
        }
        values = order.map { values[$0] }
      } else {
        values.sort {
          ((try? runtime.toNumber($0)) ?? 0) < ((try? runtime.toNumber($1)) ?? 0)
        }
      }
      for (index, value) in values.enumerated() {
        try writeTypedElement(runtime: runtime, view: object, index: index, value: value)
      }
      return .object(object)
    }
    each("reverse") { runtime, object, _ in
      var values = (0..<object.typedArrayLength).map {
        readTypedElement(runtime: runtime, view: object, index: $0)
      }
      values.reverse()
      for (index, value) in values.enumerated() {
        try writeTypedElement(runtime: runtime, view: object, index: index, value: value)
      }
      return .object(object)
    }
    each("keys") { runtime, object, _ in
      .object(
        runtime.makeArray((0..<object.typedArrayLength).map { .number(Double($0)) }))
    }
    each("values") { runtime, object, _ in
      .object(
        runtime.makeArray(
          (0..<object.typedArrayLength).map {
            readTypedElement(runtime: runtime, view: object, index: $0)
          }))
    }
    each("entries") { runtime, object, _ in
      .object(
        runtime.makeArray(
          (0..<object.typedArrayLength).map {
            .object(
              runtime.makeArray([
                .number(Double($0)),
                readTypedElement(runtime: runtime, view: object, index: $0),
              ]))
          }))
    }
  }

  static func installDataViewConstructor(into runtime: JSRuntime) {
    let proto = runtime.dataViewPrototype
    defineTypedArrayAccessors(proto: proto, runtime: runtime)
    func element(
      _ name: String, _ size: Int,
      _ read: @escaping (Data, Int, Bool) -> JSValue,
      _ write: @escaping (inout Data, Int, JSValue, Bool, JSRuntime) throws -> Void
    ) {
      proto.defineNative("get\(name)") { [weak runtime] thisArg, args in
        guard let runtime else { return .undefined }
        guard case .object(let object) = thisArg, object.typedArrayKind == "dataview" else {
          throw JSError.type("DataView method requires a DataView receiver")
        }
        let offset = args.first.flatMap { try? typedToInteger(runtime, $0) } ?? 0
        let little = args.dropFirst().first?.truthy ?? false
        let bytes = object.typedArrayBuffer?.arrayBufferData ?? Data()
        guard offset >= 0, offset + size <= object.typedArrayLength,
          object.typedArrayOffset + offset + size <= bytes.count
        else { throw JSError.range("DataView offset out of bounds") }
        return read(bytes, object.typedArrayOffset + offset, little)
      }
      proto.defineNative("set\(name)") { [weak runtime] thisArg, args in
        guard let runtime else { return .undefined }
        guard case .object(let object) = thisArg, object.typedArrayKind == "dataview",
          let buffer = object.typedArrayBuffer
        else { throw JSError.type("DataView method requires a DataView receiver") }
        let offset = args.first.flatMap { try? typedToInteger(runtime, $0) } ?? 0
        let little = args.dropFirst(2).first?.truthy ?? false
        var bytes = buffer.arrayBufferData ?? Data()
        guard offset >= 0, offset + size <= object.typedArrayLength,
          object.typedArrayOffset + offset + size <= bytes.count
        else { throw JSError.range("DataView offset out of bounds") }
        try write(
          &bytes, object.typedArrayOffset + offset, args.dropFirst().first ?? .undefined,
          little, runtime)
        buffer.arrayBufferData = bytes
        return .undefined
      }
    }
    element("Int8", 1, { bytes, at, _ in .number(Double(Int8(bitPattern: bytes[at]))) },
      { bytes, at, value, _, runtime in
        bytes[at] = UInt8(truncatingIfNeeded: runtime.toInt32(try runtime.toNumber(value)))
      })
    element("Uint8", 1, { bytes, at, _ in .number(Double(bytes[at])) },
      { bytes, at, value, _, runtime in
        bytes[at] = UInt8(truncatingIfNeeded: runtime.toUint32(try runtime.toNumber(value)))
      })
    element("Int16", 2, { bytes, at, little in
      .number(Double(Int16(bitPattern: load16(bytes, at, little))))
    }, { bytes, at, value, little, runtime in
      store16(&bytes, at, UInt16(truncatingIfNeeded: runtime.toInt32(try runtime.toNumber(value))), little)
    })
    element("Uint16", 2, { bytes, at, little in .number(Double(load16(bytes, at, little))) },
      { bytes, at, value, little, runtime in
        store16(&bytes, at, UInt16(truncatingIfNeeded: runtime.toUint32(try runtime.toNumber(value))), little)
      })
    element("Int32", 4, { bytes, at, little in
      .number(Double(Int32(bitPattern: load32(bytes, at, little))))
    }, { bytes, at, value, little, runtime in
      store32(&bytes, at, runtime.toUint32(try runtime.toNumber(value)), little)
    })
    element("Uint32", 4, { bytes, at, little in .number(Double(load32(bytes, at, little))) },
      { bytes, at, value, little, runtime in
        store32(&bytes, at, runtime.toUint32(try runtime.toNumber(value)), little)
      })
    element("Float32", 4, { bytes, at, little in
      .number(Double(Float(bitPattern: load32(bytes, at, little))))
    }, { bytes, at, value, little, runtime in
      store32(&bytes, at, Float(try runtime.toNumber(value)).bitPattern, little)
    })
    element("Float64", 8, { bytes, at, little in
      .number(Double(bitPattern: load64(bytes, at, little)))
    }, { bytes, at, value, little, runtime in
      store64(&bytes, at, (try runtime.toNumber(value)).bitPattern, little)
    })
    element("BigInt64", 8, { bytes, at, little in
      .bigint(String(Int64(bitPattern: load64(bytes, at, little))))
    }, { bytes, at, value, little, _ in
      store64(&bytes, at, uint64Modulo(try JSBigInt.parse(value)), little)
    })
    element("BigUint64", 8, { bytes, at, little in
      .bigint(String(load64(bytes, at, little)))
    }, { bytes, at, value, little, _ in
      store64(&bytes, at, uint64Modulo(try JSBigInt.parse(value)), little)
    })

    let ctor = makeConstructor(
      runtime: runtime, name: "DataView",
      call: { _ in throw JSError.type("DataView requires 'new'") },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        guard case .object(let buffer) = args.first, buffer.isArrayBuffer else {
          throw JSError.type("DataView requires an ArrayBuffer")
        }
        let bytes = buffer.arrayBufferData ?? Data()
        let offset = args.dropFirst().first.flatMap { try? typedToInteger(runtime, $0) } ?? 0
        guard offset >= 0, offset <= bytes.count else {
          throw JSError.range("Invalid DataView offset")
        }
        let count: Int
        if let third = args.dropFirst(2).first, !third.isNullish {
          count = (try? typedToInteger(runtime, third)) ?? 0
        } else {
          count = bytes.count - offset
        }
        guard count >= 0, offset + count <= bytes.count else {
          throw JSError.range("Invalid DataView length")
        }
        let object = JSObject(prototype: runtime.dataViewPrototype)
        object.typedArrayKind = "dataview"
        object.typedArrayOffset = offset
        object.typedArrayLength = count
        object.typedArrayBuffer = buffer
        return .object(object)
      })
    ctor.prototypeObject = runtime.dataViewPrototype
    publish(into: runtime, "DataView", .function(ctor))
  }

  static func load16(_ bytes: Data, _ at: Int, _ little: Bool) -> UInt16 {
    let low = UInt16(bytes[at])
    let high = UInt16(bytes[at + 1])
    return little ? low | (high << 8) : (low << 8) | high
  }

  static func load32(_ bytes: Data, _ at: Int, _ little: Bool) -> UInt32 {
    var raw: UInt32 = 0
    for offset in 0..<4 {
      let byte = UInt32(bytes[at + offset])
      raw |= little ? byte << (8 * offset) : byte << (8 * (3 - offset))
    }
    return raw
  }

  static func load64(_ bytes: Data, _ at: Int, _ little: Bool) -> UInt64 {
    var raw: UInt64 = 0
    for offset in 0..<8 {
      let byte = UInt64(bytes[at + offset])
      raw |= little ? byte << (8 * offset) : byte << (8 * (7 - offset))
    }
    return raw
  }

  static func store16(_ bytes: inout Data, _ at: Int, _ value: UInt16, _ little: Bool) {
    if little {
      bytes[at] = UInt8(value & 0xFF)
      bytes[at + 1] = UInt8((value >> 8) & 0xFF)
    } else {
      bytes[at] = UInt8((value >> 8) & 0xFF)
      bytes[at + 1] = UInt8(value & 0xFF)
    }
  }

  static func store32(_ bytes: inout Data, _ at: Int, _ value: UInt32, _ little: Bool) {
    for offset in 0..<4 {
      let shift = little ? 8 * offset : 8 * (3 - offset)
      bytes[at + offset] = UInt8((value >> shift) & 0xFF)
    }
  }

  static func store64(_ bytes: inout Data, _ at: Int, _ value: UInt64, _ little: Bool) {
    for offset in 0..<8 {
      let shift = little ? 8 * offset : 8 * (7 - offset)
      bytes[at + offset] = UInt8((value >> shift) & 0xFF)
    }
  }

  static func uint64Mod(_ decimal: String) -> UInt64 {
    var text = decimal
    var negative = false
    if text.hasPrefix("-") {
      negative = true
      text = String(text.dropFirst())
    }
    var result: UInt64 = 0
    for character in text {
      guard let digit = character.wholeNumberValue else { break }
      result = result &* 10 &+ UInt64(digit)
    }
    return negative ? (~result &+ 1) : result
  }
}

func elementBytes(kind: String) -> Int {
  switch kind {
  case "int8", "uint8", "uint8clamped": return 1
  case "int16", "uint16": return 2
  case "int32", "uint32", "float32": return 4
  case "float64", "bigint64", "biguint64": return 8
  default: return 1
  }
}

func makeTypedArrayView(
  runtime: JSRuntime, kind: String, bytes: Int, buffer: JSObject, offset: Int, count: Int
) -> JSObject {
  let proto = runtime.typedArrayKindPrototypes[kind] ?? runtime.typedArrayPrototype
  let object = JSObject(prototype: proto)
  object.typedArrayKind = kind
  object.typedArrayOffset = offset
  object.typedArrayLength = count
  object.typedArrayBuffer = buffer
  object.nativeGet = { [weak object] key in
    guard let object, object.typedArrayKind != nil,
      let index = Int(key), index >= 0, index < object.typedArrayLength
    else { return nil }
    return readTypedElement(runtime: runtime, view: object, index: index)
  }
  object.nativeSet = { [weak object] key, value in
    guard let object, let kind = object.typedArrayKind, kind != "dataview",
      let index = Int(key), index >= 0, index < object.typedArrayLength
    else { return false }
    try? writeTypedElement(runtime: runtime, view: object, index: index, value: value)
    return true
  }
  runtime.defineDataProperty(
    object, "length", .number(Double(count)), writable: false, enumerable: false,
    configurable: false)
  _ = bytes
  return object
}

func readTypedElement(runtime: JSRuntime, view: JSObject, index: Int) -> JSValue {
  guard let kind = view.typedArrayKind, kind != "dataview",
    let buffer = view.typedArrayBuffer, let data = buffer.arrayBufferData
  else { return .undefined }
  let stride = elementBytes(kind: kind)
  let at = view.typedArrayOffset + index * stride
  guard index >= 0, index < view.typedArrayLength, at >= 0, at + stride <= data.count else {
    return .undefined
  }
  let slice = data.subdata(in: at..<(at + stride))
  switch kind {
  case "int8": return .number(Double(Int8(bitPattern: slice[slice.startIndex])))
  case "uint8", "uint8clamped": return .number(Double(slice[slice.startIndex]))
  case "int16":
    return .number(Double(Int16(bitPattern: loadU16(slice))))
  case "uint16": return .number(Double(loadU16(slice)))
  case "int32":
    return .number(Double(Int32(bitPattern: loadU32(slice))))
  case "uint32": return .number(Double(loadU32(slice)))
  case "float32": return .number(Double(Float(bitPattern: loadU32(slice))))
  case "float64": return .number(Double(bitPattern: loadU64(slice)))
  case "bigint64":
    return .bigint(String(Int64(bitPattern: loadU64(slice))))
  case "biguint64": return .bigint(String(loadU64(slice)))
  default: return .undefined
  }
}

func writeTypedElement(runtime: JSRuntime, view: JSObject, index: Int, value: JSValue) throws {
  guard let kind = view.typedArrayKind, kind != "dataview",
    let buffer = view.typedArrayBuffer, var data = buffer.arrayBufferData
  else { throw JSError.type("Target must be a typed array") }
  let stride = elementBytes(kind: kind)
  let at = view.typedArrayOffset + index * stride
  guard index >= 0, index < view.typedArrayLength, at >= 0, at + stride <= data.count else {
    throw JSError.range("Typed array index out of bounds")
  }
  switch kind {
  case "int8":
    data[at] = UInt8(truncatingIfNeeded: runtime.toInt32(try runtime.toNumber(value)))
  case "uint8":
    data[at] = UInt8(truncatingIfNeeded: runtime.toUint32(try runtime.toNumber(value)))
  case "uint8clamped":
    let number = try runtime.toNumber(value)
    let clamped: Int
    if number.isNaN || number <= 0 { clamped = 0 }
    else if number >= 255 { clamped = 255 }
    else { clamped = Int(number.rounded(.toNearestOrEven)) }
    data[at] = UInt8(clamped)
  case "int16":
    storeLE(&data, at: at, value: UInt16(truncatingIfNeeded: runtime.toInt32(try runtime.toNumber(value))))
  case "uint16":
    storeLE(&data, at: at, value: UInt16(truncatingIfNeeded: runtime.toUint32(try runtime.toNumber(value))))
  case "int32":
    storeLE(&data, at: at, value: runtime.toUint32(try runtime.toNumber(value)))
  case "uint32":
    storeLE(&data, at: at, value: runtime.toUint32(try runtime.toNumber(value)))
  case "float32":
    storeLE(&data, at: at, value: Float(try runtime.toNumber(value)).bitPattern)
  case "float64":
    storeLE64(&data, at: at, value: (try runtime.toNumber(value)).bitPattern)
  case "bigint64", "biguint64":
    storeLE64(&data, at: at, value: uint64Modulo(try JSBigInt.parse(value)))
  default:
    throw JSError.type("Unknown typed array kind")
  }
  buffer.arrayBufferData = data
}

private func loadU16(_ slice: Data) -> UInt16 {
  var value: UInt16 = 0
  for (offset, byte) in slice.enumerated() { value |= UInt16(byte) << (8 * offset) }
  return value
}

private func loadU32(_ slice: Data) -> UInt32 {
  var value: UInt32 = 0
  for (offset, byte) in slice.enumerated() { value |= UInt32(byte) << (8 * offset) }
  return value
}

private func loadU64(_ slice: Data) -> UInt64 {
  var value: UInt64 = 0
  for (offset, byte) in slice.enumerated() { value |= UInt64(byte) << (8 * offset) }
  return value
}

private func storeLE(_ data: inout Data, at: Int, value: UInt16) {
  data[at] = UInt8(value & 0xFF)
  data[at + 1] = UInt8((value >> 8) & 0xFF)
}

private func storeLE(_ data: inout Data, at: Int, value: UInt32) {
  for offset in 0..<4 { data[at + offset] = UInt8((value >> (8 * offset)) & 0xFF) }
}

private func storeLE64(_ data: inout Data, at: Int, value: UInt64) {
  for offset in 0..<8 { data[at + offset] = UInt8((value >> (8 * offset)) & 0xFF) }
}

private func uint64Modulo(_ decimal: String) -> UInt64 {
  var text = decimal
  var negative = false
  if text.hasPrefix("-") {
    negative = true
    text = String(text.dropFirst())
  }
  var result: UInt64 = 0
  for character in text {
    guard let digit = character.wholeNumberValue else { break }
    result = result &* 10 &+ UInt64(digit)
  }
  return negative ? (~result &+ 1) : result
}
