import DOM
import Foundation

extension JSDOMEvents {
  public static func locationFor(context: JSDOMContext) -> JSObject {
    let object = JSObject()
    object.nativeGet = { [weak context, weak object] key in
      guard let context, let object else { return nil }
      let urlString = currentURL(object: object, context: context)
      guard let url = URL(string: urlString) else {
        if key == "href" { return .string(urlString) }
        return nil
      }
      switch key {
      case "href": return .string(urlString)
      case "protocol": return .string(url.scheme.map { $0 + ":" } ?? "")
      case "host":
        if let port = url.port { return .string("\(url.host ?? ""):\(port)") }
        return .string(url.host ?? "")
      case "hostname": return .string(url.host ?? "")
      case "port": return .string(url.port.map(String.init) ?? "")
      case "pathname": return .string(url.path.isEmpty ? "/" : url.path)
      case "search": return .string(url.query.map { "?" + $0 } ?? "")
      case "hash": return .string(url.fragment.map { "#" + $0 } ?? "")
      case "origin":
        if let scheme = url.scheme, let host = url.host {
          if let port = url.port { return .string("\(scheme)://\(host):\(port)") }
          return .string("\(scheme)://\(host)")
        }
        return .string("null")
      default: return nil
      }
    }
    object.nativeSet = { [weak context, weak object] key, value in
      guard let context, let object else { return false }
      if key == "href" {
        navigate(object: object, context: context, url: value.description)
        return true
      }
      return false
    }
    object.defineNative("assign") { [weak context, weak object] args in
      guard let context, let object,
        case .string(let url) = args.first
      else {
        return .undefined
      }
      navigate(object: object, context: context, url: url)
      return .undefined
    }
    object.defineNative("replace") { [weak context, weak object] args in
      guard let context, let object,
        case .string(let url) = args.first
      else {
        return .undefined
      }
      navigate(object: object, context: context, url: url)
      return .undefined
    }
    object.defineNative("reload") { [weak context, weak object] _ in
      guard let context, let object else { return .undefined }
      let current = currentURL(object: object, context: context)
      context.hooks().navigate?(current)
      return .undefined
    }
    object.defineNative("toString") { [weak context, weak object] _ in
      guard let context, let object else { return .string("") }
      return .string(currentURL(object: object, context: context))
    }
    return object
  }

  static func currentURL(object: JSObject, context: JSDOMContext) -> String {
    if case .string(let override) = object.properties["__url"] {
      return override
    }
    return context.hooks().currentURL?() ?? "about:blank"
  }

  static func navigate(object: JSObject, context: JSDOMContext, url: String) {
    object.properties["__url"] = .string(url)
    context.hooks().navigate?(url)
  }

  public static func navigatorFor(context: JSDOMContext) -> JSObject {
    let object = JSObject()
    let hooks = context.hooks()
    object.set("userAgent", .string(
      hooks.userAgent?() ?? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Aether/0.1"))
    object.set("platform", .string("MacIntel"))
    object.set("language", .string("en-US"))
    object.set(
      "languages",
      .object(context.arrayOf([.string("en-US"), .string("en")])))
    object.set("onLine", .bool(true))
    object.set("cookieEnabled", .bool(true))
    return object
  }

  public static func historyFor(context: JSDOMContext, location: JSObject) -> JSObject {
    let object = JSObject()
    object.set("length", .number(1))
    object.set("state", .null)
    object.set("scrollRestoration", .string("auto"))
    object.defineNative("pushState") { [weak location] args in
      if let first = args.first { object.set("__state", first) }
      else { object.set("__state", .null) }
      object.set("state", object.get("__state"))
      if args.count > 2, case .string(let url) = args[2] {
        location?.properties["__url"] = .string(url)
      }
      return .undefined
    }
    object.defineNative("replaceState") { [weak location] args in
      if let first = args.first { object.set("__state", first) }
      else { object.set("__state", .null) }
      object.set("state", object.get("__state"))
      if args.count > 2, case .string(let url) = args[2] {
        location?.properties["__url"] = .string(url)
      }
      return .undefined
    }
    object.defineNative("back") { _ in .undefined }
    object.defineNative("forward") { _ in .undefined }
    object.defineNative("go") { _ in .undefined }
    _ = context
    return object
  }

  public static func getComputedStyleFor(
    id: NodeID, context: JSDOMContext
  ) -> JSObject {
    let document = context.document
    let object = JSObject(
      nativeGet: { [weak document] key in
        guard let document, document.node(id) != nil else { return nil }
        if key == "cssText" {
          return .string(document.node(id)?.attribute("style") ?? "")
        }
        if let override = context.hooks().computedStyleHandler?(id, key) {
          return .string(override)
        }
        let properties = parseStyleAttribute(
          document.node(id)?.attribute("style") ?? "")
        let dashed = camelToDashed(key)
        if let value = properties[dashed] ?? properties[key] {
          return .string(value)
        }
        return .string("")
      },
      nativeSet: { _, _ in false })
    object.defineNative("getPropertyValue") { [weak document] args in
      guard case .string(let name) = args.first,
        let document, document.node(id) != nil
      else {
        return .string("")
      }
      if let override = context.hooks().computedStyleHandler?(id, name) {
        return .string(override)
      }
      return .string(
        parseStyleAttribute(document.node(id)?.attribute("style") ?? "")[name] ?? "")
    }
    return object
  }

  public static func makeWindow(
    context: JSDOMContext, document: JSObject, localStorage: JSObject?,
    sessionStorage: JSObject?
  ) -> JSObject {
    let object = JSObject(
      nativeGet: { [weak context] key in
        guard let context else { return nil }
        switch key {
        case "innerWidth", "outerWidth":
          return .number(context.hooks().viewportSize?().0 ?? 1280)
        case "innerHeight", "outerHeight":
          return .number(context.hooks().viewportSize?().1 ?? 800)
        case "scrollX", "scrollY", "pageXOffset", "pageYOffset":
          return .number(0)
        case "devicePixelRatio": return .number(1)
        case "name": return .string("")
        case "closed": return .bool(false)
        case "opener": return .null
        case "length": return .number(0)
        default: return nil
        }
      },
      nativeSet: { _, _ in false })
    object.set("document", .object(document))
    if let localStorage { object.set("localStorage", .object(localStorage)) }
    if let sessionStorage { object.set("sessionStorage", .object(sessionStorage)) }
    let location = locationFor(context: context)
    object.set("location", .object(location))
    object.set("navigator", .object(navigatorFor(context: context)))
    object.set("history", .object(historyFor(context: context, location: location)))
    object.set("window", .object(object))
    object.set("self", .object(object))
    object.set("parent", .object(object))
    object.set("top", .object(object))
    object.set("frames", .object(context.arrayOf([])))
    object.defineNative("alert") { args in
      context.hooks().alertHandler?(args.first?.description ?? "")
      return .undefined
    }
    object.defineNative("confirm") { args in
      .bool(context.hooks().confirmHandler?(args.first?.description ?? "") ?? false)
    }
    object.defineNative("prompt") { args in
      let message = args.first?.description ?? ""
      let fallback = args.count > 1 ? args[1].description : ""
      if let answer = context.hooks().promptHandler?(message, fallback) {
        return .string(answer)
      }
      return .null
    }
    object.defineNative("getComputedStyle") { args in
      guard case .object(let element) = args.first,
        let nodeID = element.nativeNodeID
      else {
        throw JSError.type("Argument must be an element")
      }
      return .object(getComputedStyleFor(id: nodeID, context: context))
    }
    object.defineNative("matchMedia") { args in
      let query = args.first?.description ?? ""
      let result = JSObject()
      result.set("media", .string(query))
      result.set("matches", .bool(context.hooks().mediaQueryHandler?(query) ?? false))
      result.set("onchange", .null)
      result.defineNative("addListener") { _ in .undefined }
      result.defineNative("removeListener") { _ in .undefined }
      result.defineNative("addEventListener") { _ in .undefined }
      result.defineNative("removeEventListener") { _ in .undefined }
      result.defineNative("dispatchEvent") { _ in .bool(false) }
      return .object(result)
    }
    object.defineNative("open") { _ in .null }
    object.defineNative("close") { _ in .undefined }
    object.defineNative("stop") { _ in .undefined }
    object.defineNative("focus") { _ in .undefined }
    object.defineNative("blur") { _ in .undefined }
    object.defineNative("scrollTo") { _ in .undefined }
    object.defineNative("scroll") { _ in .undefined }
    object.defineNative("scrollBy") { _ in .undefined }
    object.defineNative("getSelection") { _ in .null }
    installEventGlobals(holder: object, context: context, runtime: context.runtime)
    JSDOMBindings.installNodeListeners(
      object, id: context.document.root, events: context.events)
    return object
  }
}
