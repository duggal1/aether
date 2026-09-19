import DOM
import Foundation

func jsArrayIndex(_ key: String) -> UInt32? {
  if key.isEmpty || key.count > 10 { return nil }
  guard key.allSatisfy({ $0.isNumber }) else { return nil }
  if key.count > 1 && key.hasPrefix("0") { return nil }
  guard let raw = UInt64(key), raw < 4294967295 else { return nil }
  return UInt32(raw)
}

extension JSObject {
  func defineNative(
    _ name: String,
    _ body: @escaping (JSValue, [JSValue]) throws -> JSValue
  ) {
    set(name, .function(JSFunction(nativeMethod: body, name: name)))
  }

  func defineNative(
    _ name: String,
    _ body: @escaping ([JSValue]) throws -> JSValue
  ) {
    set(name, .function(JSFunction(native: body, name: name)))
  }
}

public enum JSBuiltins {
  public static func install(into runtime: JSRuntime) {
    runtime.objectPrototype.prototype = nil
    runtime.functionPrototype.prototype = runtime.objectPrototype
    runtime.arrayPrototype.prototype = runtime.objectPrototype
    runtime.stringPrototype.prototype = runtime.objectPrototype
    runtime.numberPrototype.prototype = runtime.objectPrototype
    runtime.booleanPrototype.prototype = runtime.objectPrototype
    runtime.errorPrototype.prototype = runtime.objectPrototype
    runtime.regexpPrototype.prototype = runtime.objectPrototype
    runtime.promisePrototype.prototype = runtime.objectPrototype
    runtime.mapPrototype.prototype = runtime.objectPrototype
    runtime.setPrototype.prototype = runtime.objectPrototype
    runtime.arrayBufferPrototype.prototype = runtime.objectPrototype
    runtime.typedArrayPrototype.prototype = runtime.objectPrototype
    runtime.dataViewPrototype.prototype = runtime.objectPrototype
    runtime.datePrototype.prototype = runtime.objectPrototype
    runtime.symbolPrototype.prototype = runtime.objectPrototype
    installFunctionPrototype(into: runtime)
    installObject(into: runtime)
    installErrors(into: runtime)
    installJSON(into: runtime)
    installMath(into: runtime)
    installSymbol(into: runtime)
    installMapSet(into: runtime)
    installDate(into: runtime)
    installRegExp(into: runtime)
    installArray(into: runtime)
    installString(into: runtime)
    installNumberBoolean(into: runtime)
  }

  static func publish(into runtime: JSRuntime, _ name: String, _ value: JSValue) {
    runtime.globals.define(name, value: value)
    runtime.globalObject.set(name, value)
  }

  static func makeConstructor(
    runtime: JSRuntime, name: String,
    call: @escaping ([JSValue]) throws -> JSValue,
    construct: @escaping ([JSValue]) throws -> JSValue,
    parentPrototype: JSObject? = nil
  ) -> JSFunction {
    let constructor = JSFunction(native: { [weak runtime] args in
      guard runtime != nil else { return .undefined }
      return try call(args)
    }, name: name)
    constructor.constructNative = { [weak runtime] args in
      guard runtime != nil else { return .undefined }
      return try construct(args)
    }
    constructor.prototypeObject = JSObject(
      prototype: parentPrototype ?? runtime.objectPrototype)
    constructor.prototypeObject?.set(
      "constructor", .function(constructor))
    return constructor
  }

  static func installFunctionPrototype(into runtime: JSRuntime) {
    let proto = runtime.functionPrototype
    proto.defineNative("call") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .function = thisArg else {
        throw JSError.type("call on incompatible receiver")
      }
      let receiver = args.first ?? .undefined
      return try runtime.callValue(
        thisArg, thisValue: receiver, arguments: Array(args.dropFirst()))
    }
    proto.defineNative("apply") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .function = thisArg else {
        throw JSError.type("apply on incompatible receiver")
      }
      let receiver = args.first ?? .undefined
      var list: [JSValue] = []
      if args.count > 1, !args[1].isNullish {
        guard let items = try runtime.iterateValues(args[1]) else {
          throw JSError.type("Argument list must be iterable")
        }
        list = items
      }
      return try runtime.callValue(thisArg, thisValue: receiver, arguments: list)
    }
    proto.defineNative("bind") { [weak runtime] thisArg, args in
      guard case .function(let function) = thisArg else {
        throw JSError.type("bind on incompatible receiver")
      }
      let bound = JSFunction(patterns: [], body: [], closure: function.closure,
        name: "bound \(function.name)")
      bound.boundTarget = function
      bound.boundThis = args.first
      bound.boundArguments = Array(args.dropFirst())
      if !function.parameters.isEmpty {
        let remaining = max(0, function.parameters.count - bound.boundArguments.count)
        bound.staticProperties.set("length", .number(Double(remaining)))
      }
      return .function(bound)
    }
    proto.defineNative("toString") { thisArg, _ in
      if case .function(let function) = thisArg {
        return .string("function \(function.name)() { [native code] }")
      }
      throw JSError.type("toString on incompatible receiver")
    }
  }

  static func installObject(into runtime: JSRuntime) {
    let proto = runtime.objectPrototype
    proto.defineNative("hasOwnProperty") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let key = try runtime.toString(args.first ?? .undefined)
      if case .object(let object) = thisArg { return .bool(object.hasOwn(key)) }
      return .bool(false)
    }
    proto.defineNative("isPrototypeOf") { [weak runtime] thisArg, args in
      guard case .object(let candidate) = thisArg else { return .bool(false) }
      guard case .object(let object) = args.first else { return .bool(false) }
      var current = object.prototype
      var depth = 0
      while let node = current, depth < 128 {
        depth += 1
        if node === candidate { return .bool(true) }
        current = node.prototype
      }
      return .bool(false)
    }
    proto.defineNative("propertyIsEnumerable") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let key = try runtime.toString(args.first ?? .undefined)
      guard case .object(let object) = thisArg else { return .bool(false) }
      guard object.hasOwn(key) else { return .bool(false) }
      return .bool(object.attributes[key]?.enumerable ?? true)
    }
    proto.defineNative("toString") { [weak runtime] thisArg, _ in
      guard let runtime else { return .undefined }
      if case .object(let object) = thisArg {
        return .string(runtime.defaultObjectString(object))
      }
      return .string("[object Object]")
    }
    proto.defineNative("valueOf") { thisArg, _ in return thisArg }
    proto.defineNative("__defineGetter__") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be an object")
      }
      let key = try runtime.toString(args.first ?? .undefined)
      guard case .function(let getter) = args.dropFirst().first ?? .undefined else {
        throw JSError.type("Getter must be callable")
      }
      runtime.defineAccessor(object, key, getter: getter,
        setter: object.accessorSet[key])
      return .undefined
    }

    let constructor = makeConstructor(
      runtime: runtime, name: "Object",
      call: { [weak runtime] args in
        guard let runtime else { return .undefined }
        if let first = args.first, !first.isNullish {
          return try runtime.toObject(first)
        }
        return .object(JSObject(prototype: runtime.objectPrototype))
      },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        if let first = args.first, !first.isNullish {
          return try runtime.toObject(first)
        }
        return .object(JSObject(prototype: runtime.objectPrototype))
      })
    publish(into: runtime, "Object", .function(constructor))
    constructor.prototypeObject = runtime.objectPrototype
    runtime.objectPrototype.set("constructor", .function(constructor))
    let statics = constructor.staticProperties
    statics.defineNative("create") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      let parent: JSObject?
      if let first = args.first {
        if first.isNullish {
          parent = nil
        } else if case .object(let object) = first {
          parent = object
        } else {
          throw JSError.type("Prototype must be an object or null")
        }
      } else {
        parent = runtime.objectPrototype
      }
      let object = JSObject(prototype: parent)
      if args.count > 1, case .object(let descriptors) = args[1] {
        try definePropertiesFrom(runtime: runtime, target: object, source: descriptors)
      }
      return .object(object)
    }
    statics.defineNative("keys") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = try runtime.toObject(args.first ?? .undefined) else {
        return .object(runtime.makeArray([]))
      }
      return .object(runtime.makeArray(object.ownEnumerableKeys().map { .string($0) }))
    }
    statics.defineNative("values") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = try runtime.toObject(args.first ?? .undefined) else {
        return .object(runtime.makeArray([]))
      }
      var values: [JSValue] = []
      for key in object.ownEnumerableKeys() {
        values.append(runtime.runtimeRead(object, key))
      }
      return .object(runtime.makeArray(values))
    }
    statics.defineNative("entries") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = try runtime.toObject(args.first ?? .undefined) else {
        return .object(runtime.makeArray([]))
      }
      var pairs: [JSValue] = []
      for key in object.ownEnumerableKeys() {
        pairs.append(.object(runtime.makeArray([.string(key), runtime.runtimeRead(object, key)])))
      }
      return .object(runtime.makeArray(pairs))
    }
    statics.defineNative("assign") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard !args.isEmpty else { return .undefined }
      let target = try runtime.toObject(args[0])
      guard case .object(let targetObject) = target else { return target }
      for source in args.dropFirst() {
        if source.isNullish { continue }
        guard case .object(let sourceObject) = try runtime.toObject(source) else { continue }
        for key in sourceObject.ownEnumerableKeys() {
          targetObject.set(key, runtime.runtimeRead(sourceObject, key))
        }
        for (id, value) in sourceObject.symbolProperties {
          targetObject.symbolProperties[id] = value
        }
      }
      return target
    }
    statics.defineNative("defineProperty") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard args.count > 2, case .object(let object) = args[0] else {
        throw JSError.type("Target must be an object")
      }
      let key = try runtime.toString(args[1])
      guard case .object(let descriptor) = args[2] else {
        throw JSError.type("Descriptor must be an object")
      }
      try applyPropertyDescriptor(runtime: runtime, target: object, key: key,
        descriptor: descriptor)
      return .object(object)
    }
    statics.defineNative("defineProperties") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard args.count > 1, case .object(let object) = args[0],
        case .object(let descriptors) = args[1]
      else {
        throw JSError.type("Invalid arguments")
      }
      try definePropertiesFrom(runtime: runtime, target: object, source: descriptors)
      return .object(object)
    }
    statics.defineNative("getOwnPropertyDescriptor") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = try runtime.toObject(args.first ?? .undefined) else {
        return .undefined
      }
      let key = try runtime.toString(args.count > 1 ? args[1] : .undefined)
      guard object.hasOwn(key) || object.accessorGet[key] != nil
        || object.accessorSet[key] != nil
      else {
        return .undefined
      }
      let descriptor = JSObject(prototype: runtime.objectPrototype)
      if let getter = object.accessorGet[key] {
        descriptor.set("get", .function(getter))
      } else {
        descriptor.set("get", .undefined)
      }
      if let setter = object.accessorSet[key] {
        descriptor.set("set", .function(setter))
      } else {
        descriptor.set("set", .undefined)
      }
      if object.hasOwn(key) {
        descriptor.set("value", object.get(key))
      }
      let attributes = object.attributes[key] ?? JSPropertyAttributes.default
      descriptor.set("writable", .bool(attributes.writable))
      descriptor.set("enumerable", .bool(attributes.enumerable))
      descriptor.set("configurable", .bool(attributes.configurable))
      return .object(descriptor)
    }
    statics.defineNative("getOwnPropertyNames") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = try runtime.toObject(args.first ?? .undefined) else {
        return .object(runtime.makeArray([]))
      }
      var keys = Set(object.properties.keys)
      keys.formUnion(object.accessorGet.keys)
      keys.formUnion(object.accessorSet.keys)
      return .object(runtime.makeArray(keys.sorted().map { .string($0) }))
    }
    statics.defineNative("getPrototypeOf") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = try runtime.toObject(args.first ?? .undefined) else {
        return .null
      }
      if let proto = object.prototype { return .object(proto) }
      return .null
    }
    statics.defineNative("setPrototypeOf") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard args.count > 1, case .object(let object) = args[0] else {
        throw JSError.type("Target must be an object")
      }
      let parent: JSObject?
      if args[1].isNullish {
        parent = nil
      } else if case .object(let proto) = args[1] {
        var current: JSObject? = proto
        var depth = 0
        while let node = current, depth < 128 {
          depth += 1
          if node === object {
            throw JSError.type("Cyclic prototype value")
          }
          current = node.prototype
        }
        parent = proto
      } else {
        return args[0]
      }
      object.prototype = parent
      return args[0]
    }
    statics.defineNative("hasOwn") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard args.count > 1,
        case .object(let object) = try runtime.toObject(args[0])
      else {
        return .bool(false)
      }
      return .bool(object.hasOwn(try runtime.toString(args[1])))
    }
    statics.defineNative("freeze") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      if case .object(let object) = args.first {
        for key in object.properties.keys {
          var attributes = object.attributes[key] ?? JSPropertyAttributes.default
          attributes.writable = false
          attributes.configurable = false
          object.attributes[key] = attributes
        }
        object.isExtensible = false
      }
      return args.first ?? .undefined
    }
    statics.defineNative("seal") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      if case .object(let object) = args.first {
        for key in object.properties.keys {
          var attributes = object.attributes[key] ?? JSPropertyAttributes.default
          attributes.configurable = false
          object.attributes[key] = attributes
        }
        object.isExtensible = false
      }
      return args.first ?? .undefined
    }
    statics.defineNative("preventExtensions") { [weak runtime] _, args in
      if case .object(let object) = args.first { object.isExtensible = false }
      return args.first ?? .undefined
    }
    statics.defineNative("isExtensible") { _, args in
      if case .object(let object) = args.first { return .bool(object.isExtensible) }
      return .bool(false)
    }
    statics.defineNative("isFrozen") { _, args in
      guard case .object(let object) = args.first else { return .bool(true) }
      if object.isExtensible { return .bool(false) }
      for key in object.properties.keys {
        let attributes = object.attributes[key] ?? JSPropertyAttributes.default
        if attributes.writable || attributes.configurable { return .bool(false) }
      }
      return .bool(true)
    }
    statics.defineNative("isSealed") { _, args in
      guard case .object(let object) = args.first else { return .bool(true) }
      if object.isExtensible { return .bool(false) }
      for key in object.properties.keys {
        let attributes = object.attributes[key] ?? JSPropertyAttributes.default
        if attributes.configurable { return .bool(false) }
      }
      return .bool(true)
    }
    statics.defineNative("fromEntries") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard let items = try runtime.iterateValues(args.first ?? .undefined) else {
        throw JSError.type("Argument is not iterable")
      }
      let object = JSObject(prototype: runtime.objectPrototype)
      for item in items {
        guard let pair = try runtime.iterateValues(item), pair.count >= 2 else {
          throw JSError.type("Entry must be iterable")
        }
        object.set(try runtime.toString(pair[0]), pair[1])
      }
      return .object(object)
    }
    statics.defineNative("is") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard args.count > 1 else { return .bool(false) }
      if case .number(let a) = args[0], case .number(let b) = args[1] {
        if a.isNaN && b.isNaN { return .bool(true) }
        if a == 0 && b == 0 { return .bool((1 / a) == (1 / b)) }
        return .bool(a == b)
      }
      return .bool(runtime.strictEqual(args[0], args[1]))
    }
    let prototypeObject = JSObject(prototype: runtime.objectPrototype)
    statics.set("prototype", .object(prototypeObject))
  }

  static func definePropertiesFrom(
    runtime: JSRuntime, target: JSObject, source: JSObject
  ) throws {
    for key in source.ownEnumerableKeys() {
      guard case .object(let descriptor) = runtime.runtimeRead(source, key) else {
        throw JSError.type("Descriptor must be an object")
      }
      try applyPropertyDescriptor(
        runtime: runtime, target: target, key: key, descriptor: descriptor)
    }
  }

  static func applyPropertyDescriptor(
    runtime: JSRuntime, target: JSObject, key: String, descriptor: JSObject
  ) throws {
    if !target.isExtensible && !target.hasOwn(key) {
      throw JSError.type("Cannot define property \(key)")
    }
    if target.attributes[key]?.configurable == false {
      throw JSError.type("Cannot redefine property \(key)")
    }
    let hasValue = descriptor.hasOwn("value") || descriptor.accessorGet["value"] != nil
    let hasGetter = descriptor.hasOwn("get") || descriptor.accessorGet["get"] != nil
    let hasSetter = descriptor.hasOwn("set") || descriptor.accessorSet["set"] != nil
    if (hasGetter || hasSetter) && hasValue {
      throw JSError.type("Invalid property descriptor")
    }
    if hasGetter || hasSetter {
      let getter: JSFunction?
      let setter: JSFunction?
      let rawGet = descriptor.get("get")
      let rawSet = descriptor.get("set")
      if case .function(let function) = rawGet {
        getter = function
      } else if rawGet.isNullish {
        getter = nil
      } else {
        throw JSError.type("Getter must be callable")
      }
      if case .function(let function) = rawSet {
        setter = function
      } else if rawSet.isNullish {
        setter = nil
      } else {
        throw JSError.type("Setter must be callable")
      }
      if target.hasOwn(key) { target.properties.removeValue(forKey: key) }
      runtime.defineAccessor(
        target, key, getter: getter, setter: setter,
        enumerable: descriptor.get("enumerable").truthy,
        configurable: descriptor.get("configurable").truthy)
      if !descriptor.hasOwn("enumerable") && !descriptor.hasOwn("configurable") {
        target.attributes[key] = JSPropertyAttributes(
          writable: false, enumerable: false, configurable: false)
      }
      return
    }
    let value = descriptor.hasOwn("value") ? descriptor.get("value") : target.get(key)
    let writable = descriptor.hasOwn("writable")
      ? descriptor.get("writable").truthy : false
    let enumerable = descriptor.hasOwn("enumerable")
      ? descriptor.get("enumerable").truthy : false
    let configurable = descriptor.hasOwn("configurable")
      ? descriptor.get("configurable").truthy : false
    target.properties[key] = value
    target.attributes[key] = JSPropertyAttributes(
      writable: writable, enumerable: enumerable, configurable: configurable)
    target.accessorGet.removeValue(forKey: key)
    target.accessorSet.removeValue(forKey: key)
  }
}
