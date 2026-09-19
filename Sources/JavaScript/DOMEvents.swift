import DOM
import Foundation

public enum JSDOMEvents {
  public static func makeEvent(kind: String, context: JSDOMContext) -> JSObject {
    let normalized = kind.lowercased()
    let proto: JSObject
    switch normalized {
    case "customevent":
      proto = context.customEventPrototype
    case "mouseevents", "mouseevent":
      proto = context.mouseEventPrototype
    case "keyboardevents", "keyboardevent", "focusevent":
      proto = context.keyboardEventPrototype
    default:
      proto = context.eventPrototype
    }
    let object = JSObject(prototype: proto)
    object.set("type", .string(""))
    object.set("bubbles", .bool(false))
    object.set("cancelable", .bool(false))
    object.set("composed", .bool(false))
    object.set("target", .null)
    object.set("currentTarget", .null)
    object.set("eventPhase", .number(0))
    object.set("defaultPrevented", .bool(false))
    object.set("timeStamp", .number(Date().timeIntervalSince1970 * 1000))
    object.set("__prevented", .bool(false))
    object.set("__stopped", .bool(false))
    object.set("__immediate", .bool(false))
    installEventMethods(object, mouse: normalized.contains("mouse"),
      keyboard: normalized.contains("keyboard"))
    return object
  }

  static func installEventMethods(_ object: JSObject, mouse: Bool, keyboard: Bool) {
    _ = mouse
    _ = keyboard
    object.defineNative("preventDefault") { thisArg, _ in
      if case .object(let event) = thisArg {
        event.set("__prevented", .bool(true))
        event.set("defaultPrevented", .bool(true))
      }
      return .undefined
    }
    object.defineNative("stopPropagation") { thisArg, _ in
      if case .object(let event) = thisArg {
        event.set("__stopped", .bool(true))
      }
      return .undefined
    }
    object.defineNative("stopImmediatePropagation") { thisArg, _ in
      if case .object(let event) = thisArg {
        event.set("__stopped", .bool(true))
        event.set("__immediate", .bool(true))
      }
      return .undefined
    }
    object.defineNative("initEvent") { thisArg, args in
      guard case .object(let event) = thisArg else { return .undefined }
      if let first = args.first { event.set("type", first) }
      if args.count > 1 { event.set("bubbles", .bool(args[1].truthy)) }
      if args.count > 2 { event.set("cancelable", .bool(args[2].truthy)) }
      return .undefined
    }
  }

  public static func installEventGlobals(
    holder: JSObject, context: JSDOMContext, runtime: JSRuntime?
  ) {
    _ = runtime
    context.eventPrototype.set("constructor", .string("Event"))
    holder.set("Event", .function(eventConstructor(kind: "Event", context: context)))
    holder.set("CustomEvent", .function(eventConstructor(kind: "CustomEvent", context: context)))
    holder.set("MouseEvent", .function(eventConstructor(kind: "MouseEvent", context: context)))
    holder.set(
      "KeyboardEvent", .function(eventConstructor(kind: "KeyboardEvent", context: context)))
    holder.set("FocusEvent", .function(eventConstructor(kind: "FocusEvent", context: context)))
  }

  static func eventConstructor(kind: String, context: JSDOMContext) -> JSFunction {
    JSFunction(native: { args in
      let object = makeEvent(kind: kind, context: context)
      if let first = args.first {
        object.set("type", first)
      }
      if args.count > 1, case .object(let options) = args[1] {
        for key in ["bubbles", "cancelable", "composed"] {
          if options.hasOwn(key) {
            object.set(key, .bool(options.get(key).truthy))
          }
        }
        if options.hasOwn("detail") {
          object.set("detail", options.get("detail"))
        }
        for key in [
          "clientX", "clientY", "screenX", "screenY", "button", "buttons", "ctrlKey",
          "shiftKey", "altKey", "metaKey", "key", "code", "keyCode", "charCode",
          "which", "location", "repeat",
        ] {
          if options.hasOwn(key) {
            object.set(key, options.get(key))
          }
        }
      }
      if kind == "CustomEvent", !hasOwnValue(object, "detail") {
        object.set("detail", .null)
      }
      return .object(object)
    }, name: kind)
  }

  static func hasOwnValue(_ object: JSObject, _ key: String) -> Bool {
    object.hasOwn(key)
  }

  public static func installNodeExtras(_ object: JSObject, id: NodeID, context: JSDOMContext) {
    object.set("classList", .object(classListFor(id: id, context: context)))
    object.set("dataset", .object(datasetFor(id: id, context: context)))
    object.set("style", .object(styleFor(id: id, context: context)))
  }

  public static func classListFor(id: NodeID, context: JSDOMContext) -> JSObject {
    let document = context.document
    let object = JSObject()
    func current() -> [String] {
      (document.node(id)?.attribute("class") ?? "")
        .split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
    func commit(_ classes: [String]) {
      document.setAttribute("class", value: classes.joined(separator: " "), on: id)
    }
    object.defineNative("add") { args in
      var classes = current()
      for argument in args {
        let token = argument.description
        if !token.isEmpty, !classes.contains(token) { classes.append(token) }
      }
      commit(classes)
      return .undefined
    }
    object.defineNative("remove") { args in
      let banned = Set(args.map { $0.description })
      commit(current().filter { !banned.contains($0) })
      return .undefined
    }
    object.defineNative("toggle") { args in
      guard let first = args.first else { return .bool(false) }
      let token = first.description
      var classes = current()
      let present = classes.contains(token)
      let force: Bool? = args.count > 1 ? args[1].truthy : nil
      let shouldHave = force ?? !present
      if shouldHave, !present { classes.append(token) }
      if !shouldHave { classes.removeAll { $0 == token } }
      commit(classes)
      return .bool(shouldHave)
    }
    object.defineNative("contains") { args in
      guard let first = args.first else { return .bool(false) }
      return .bool(current().contains(first.description))
    }
    object.defineNative("replace") { args in
      guard args.count > 1 else { return .bool(false) }
      var classes = current()
      guard let position = classes.firstIndex(of: args[0].description) else {
        return .bool(false)
      }
      classes[position] = args[1].description
      commit(classes)
      return .bool(true)
    }
    object.defineNative("item") { args in
      guard case .number(let number) = args.first else { return .null }
      let classes = current()
      let index = Int(number)
      if classes.indices.contains(index) { return .string(classes[index]) }
      return .null
    }
    return object
  }

  public static func datasetFor(id: NodeID, context: JSDOMContext) -> JSObject {
    let document = context.document
    let object = JSObject(
      nativeGet: { [weak document] key in
        guard let document, let node = document.node(id) else { return nil }
        let dashed = "data-" + camelToDashed(key)
        return node.attribute(dashed).map(JSValue.string)
      },
      nativeSet: { [weak document] key, value in
        guard let document, document.node(id) != nil else { return false }
        document.setAttribute("data-" + camelToDashed(key), value: value.description, on: id)
        return true
      })
    return object
  }

  public static func styleFor(id: NodeID, context: JSDOMContext) -> JSObject {
    let document = context.document
    let object = JSObject(
      nativeGet: { [weak document] key in
        guard let document, let node = document.node(id) else { return nil }
        if key == "cssText" {
          return .string(node.attribute("style") ?? "")
        }
        let properties = parseStyleAttribute(node.attribute("style") ?? "")
        let dashed = camelToDashed(key)
        if let value = properties[dashed] ?? properties[key] {
          return .string(value)
        }
        return nil
      },
      nativeSet: { [weak document] key, value in
        guard let document, document.node(id) != nil else { return false }
        if key == "cssText" {
          document.setAttribute("style", value: value.description, on: id)
          return true
        }
        var properties = parseStyleAttribute(
          document.node(id)?.attribute("style") ?? "")
        properties[camelToDashed(key)] = value.description
        document.setAttribute("style", value: serializeStyle(properties), on: id)
        return true
      })
    object.defineNative("getPropertyValue") { [weak document] args in
      guard case .string(let name) = args.first,
        let node = document?.node(id)
      else {
        return .string("")
      }
      return .string(parseStyleAttribute(node.attribute("style") ?? "")[name] ?? "")
    }
    object.defineNative("setProperty") { [weak document] args in
      guard args.count > 1, case .string(let name) = args[0],
        let document, document.node(id) != nil
      else {
        return .undefined
      }
      var properties = parseStyleAttribute(
        document.node(id)?.attribute("style") ?? "")
      properties[name] = args[1].description
      document.setAttribute("style", value: serializeStyle(properties), on: id)
      return .undefined
    }
    object.defineNative("removeProperty") { [weak document] args in
      guard case .string(let name) = args.first,
        let document, document.node(id) != nil
      else {
        return .string("")
      }
      var properties = parseStyleAttribute(
        document.node(id)?.attribute("style") ?? "")
      let old = properties.removeValue(forKey: name) ?? ""
      document.setAttribute("style", value: serializeStyle(properties), on: id)
      return .string(old)
    }
    return object
  }

  static func camelToDashed(_ key: String) -> String {
    var result = ""
    for character in key {
      if character.isUppercase {
        result.append("-")
        result.append(contentsOf: character.lowercased())
      } else {
        result.append(character)
      }
    }
    return result
  }

  static func parseStyleAttribute(_ text: String) -> [String: String] {
    var properties: [String: String] = [:]
    for declaration in text.split(separator: ";") {
      let parts = declaration.split(separator: ":", maxSplits: 1)
      if parts.count == 2 {
        let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { properties[name] = value }
      }
    }
    return properties
  }

  static func serializeStyle(_ properties: [String: String]) -> String {
    properties.sorted(by: { $0.key < $1.key })
      .map { "\($0.key): \($0.value);" }.joined(separator: " ")
  }
}
