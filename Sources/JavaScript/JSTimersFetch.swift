import DOM
import Foundation
import Storage

private struct FetchBox: @unchecked Sendable {
  weak var runtime: JSRuntime?
}

private enum FetchOutcome: Sendable {
  case ok(status: Int, headers: [String: String], url: String, body: Data)
  case failure(String)
}

extension JSRuntime {
  func registerFetchCapability(_ capability: JSPromiseCapability) -> UInt64 {
    let id = nextFetchCapabilityID
    nextFetchCapabilityID &+= 1
    fetchCapabilities[id] = capability
    return id
  }

  func takeFetchCapability(_ id: UInt64) -> JSPromiseCapability? {
    fetchCapabilities.removeValue(forKey: id)
  }

  func installTimerGlobals() {
    globals.define(
      "setTimeout",
      value: .function(
        JSFunction(native: { [weak self] args in
          guard let self else { return .undefined }
          let callback = try self.makeTimerCallback(
            from: args.first, extra: Array(args.dropFirst(2)))
          let id = try self.callTimerHost(
            milliseconds: Self.timerDelay(args.count > 1 ? args[1] : .undefined),
            repeats: false, callback: callback)
          return .number(id)
        }, name: "setTimeout")))
    globals.define(
      "clearTimeout",
      value: .function(
        JSFunction(native: { [weak self] args in
          if case .number(let id) = args.first { self?.clearTimerHost(id: id) }
          return .undefined
        }, name: "clearTimeout")))
    globals.define(
      "setInterval",
      value: .function(
        JSFunction(native: { [weak self] args in
          guard let self else { return .undefined }
          let callback = try self.makeTimerCallback(
            from: args.first, extra: Array(args.dropFirst(2)))
          let id = try self.callTimerHost(
            milliseconds: Self.timerDelay(args.count > 1 ? args[1] : .undefined),
            repeats: true, callback: callback)
          return .number(id)
        }, name: "setInterval")))
    globals.define(
      "clearInterval",
      value: .function(
        JSFunction(native: { [weak self] args in
          if case .number(let id) = args.first { self?.clearTimerHost(id: id) }
          return .undefined
        }, name: "clearInterval")))
  }

  private static func timerDelay(_ value: JSValue) -> Double {
    guard case .number(let raw) = value, raw.isFinite else { return 0 }
    return min(max(0, raw), 2_147_483_647)
  }

  private func makeTimerCallback(from value: JSValue?, extra: [JSValue]) throws -> JSFunction {
    if case .function(let callback) = value {
      guard !extra.isEmpty else { return callback }
      return JSFunction(native: { [weak self] _ in
        guard let self else { return .undefined }
        return try self.callFunction(callback, arguments: extra)
      })
    }
    throw JSError.type("Timer callback must be a function")
  }

  func installFetchGlobals() {
    headersPrototype.prototype = objectPrototype
    requestPrototype.prototype = objectPrototype
    responsePrototype.prototype = objectPrototype
    installHeadersConstructor()
    installRequestConstructor()
    installResponseConstructor()
    installFetchFunction()
  }

  private func publishGlobal(_ name: String, _ value: JSValue) {
    globals.define(name, value: value)
    globalObject.set(name, value)
  }

  func makeHeaders(_ fields: [(name: String, value: String)]) -> JSObject {
    let object = JSObject(prototype: headersPrototype)
    object.headerFields = fields
    return object
  }

  func headersFrom(_ value: JSValue) throws -> [(name: String, value: String)] {
    if value.isNullish { return [] }
    if case .object(let object) = value, let fields = object.headerFields { return fields }
    if let pairs = try iterateValues(value) {
      var fields: [(name: String, value: String)] = []
      for pair in pairs {
        guard let items = try iterateValues(pair), items.count >= 2 else {
          throw JSError.type("Header entry must be a name/value pair")
        }
        fields.append(
          (name: try validatedHeaderName(try toString(items[0])),
            value: try validatedHeaderValue(try toString(items[1]))))
      }
      return fields
    }
    if case .object(let object) = value {
      var fields: [(name: String, value: String)] = []
      for key in object.ownEnumerableKeys() {
        fields.append(
          (name: try validatedHeaderName(key),
            value: try validatedHeaderValue(try toString(object.get(key)))))
      }
      return fields
    }
    throw JSError.type("Headers initializer must be an object or sequence")
  }

  private func validatedHeaderName(_ name: String) throws -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
      trimmed.unicodeScalars.allSatisfy({ isTokenScalar($0.value) })
    else {
      throw JSError.type("Invalid header name \(name)")
    }
    return trimmed.lowercased()
  }

  private func validatedHeaderValue(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.unicodeScalars.allSatisfy({ $0.value != 0x0A && $0.value != 0x0D }) else {
      throw JSError.type("Invalid header value")
    }
    return trimmed
  }

  private func isTokenScalar(_ scalar: UInt32) -> Bool {
    if scalar >= 0x30 && scalar <= 0x39 { return true }
    if scalar >= 0x41 && scalar <= 0x5A { return true }
    if scalar >= 0x61 && scalar <= 0x7A { return true }
    return "!#$%&'*+-.^_`|~".unicodeScalars.contains(where: { $0.value == scalar })
  }

  private func installHeadersConstructor() {
    let build: ([JSValue]) throws -> JSValue = { [weak self] args in
      guard let self else { return .undefined }
      return .object(self.makeHeaders(try self.headersFrom(args.first ?? .undefined)))
    }
    let constructor = JSFunction(native: build, name: "Headers")
    constructor.constructNative = build
    constructor.prototypeObject = headersPrototype
    headersPrototype.set("constructor", .function(constructor))
    headersPrototype.set(
      "get",
      .function(
        JSFunction(nativeMethod: { thisValue, args in
          guard case .object(let object) = thisValue, let fields = object.headerFields
          else { throw JSError.type("Receiver must be a Headers object") }
          guard case .string(let name) = args.first else { return .null }
          let needle = name.lowercased()
          let matches = fields.filter { $0.name == needle }.map { $0.value }
          return matches.isEmpty ? .null : .string(matches.joined(separator: ", "))
        }, name: "get")))
    headersPrototype.set(
      "set",
      .function(
        JSFunction(nativeMethod: { [weak self] thisValue, args in
          guard let self else { return .undefined }
          guard case .object(let object) = thisValue, object.headerFields != nil
          else { throw JSError.type("Receiver must be a Headers object") }
          guard args.count > 1, case .string(let rawName) = args[0] else {
            throw JSError.type("Header name must be a string")
          }
          let name = try self.validatedHeaderName(rawName)
          let value = try self.validatedHeaderValue(try self.toString(args[1]))
          var fields = object.headerFields ?? []
          fields.removeAll { $0.name == name }
          fields.append((name: name, value: value))
          object.headerFields = fields
          return .undefined
        }, name: "set")))
    headersPrototype.set(
      "append",
      .function(
        JSFunction(nativeMethod: { [weak self] thisValue, args in
          guard let self else { return .undefined }
          guard case .object(let object) = thisValue, object.headerFields != nil
          else { throw JSError.type("Receiver must be a Headers object") }
          guard args.count > 1, case .string(let rawName) = args[0] else {
            throw JSError.type("Header name must be a string")
          }
          let name = try self.validatedHeaderName(rawName)
          let value = try self.validatedHeaderValue(try self.toString(args[1]))
          object.headerFields = (object.headerFields ?? []) + [(name: name, value: value)]
          return .undefined
        }, name: "append")))
    headersPrototype.set(
      "delete",
      .function(
        JSFunction(nativeMethod: { thisValue, args in
          guard case .object(let object) = thisValue, object.headerFields != nil
          else { throw JSError.type("Receiver must be a Headers object") }
          guard case .string(let name) = args.first else { return .undefined }
          object.headerFields = (object.headerFields ?? []).filter {
            $0.name != name.lowercased()
          }
          return .undefined
        }, name: "delete")))
    headersPrototype.set(
      "has",
      .function(
        JSFunction(nativeMethod: { thisValue, args in
          guard case .object(let object) = thisValue, let fields = object.headerFields
          else { throw JSError.type("Receiver must be a Headers object") }
          guard case .string(let name) = args.first else { return .bool(false) }
          return .bool(fields.contains { $0.name == name.lowercased() })
        }, name: "has")))
    headersPrototype.set(
      "keys",
      .function(
        JSFunction(nativeMethod: { [weak self] thisValue, _ in
          guard let self else { return .undefined }
          guard case .object(let object) = thisValue, let fields = object.headerFields
          else { throw JSError.type("Receiver must be a Headers object") }
          return .object(self.makeArray(fields.map { .string($0.name) }))
        }, name: "keys")))
    headersPrototype.set(
      "values",
      .function(
        JSFunction(nativeMethod: { [weak self] thisValue, _ in
          guard let self else { return .undefined }
          guard case .object(let object) = thisValue, let fields = object.headerFields
          else { throw JSError.type("Receiver must be a Headers object") }
          return .object(self.makeArray(fields.map { .string($0.value) }))
        }, name: "values")))
    headersPrototype.set(
      "entries",
      .function(
        JSFunction(nativeMethod: { [weak self] thisValue, _ in
          guard let self else { return .undefined }
          guard case .object(let object) = thisValue, let fields = object.headerFields
          else { throw JSError.type("Receiver must be a Headers object") }
          return .object(
            self.makeArray(fields.map {
              .object(self.makeArray([.string($0.name), .string($0.value)]))
            }))
        }, name: "entries")))
    headersPrototype.set(
      "forEach",
      .function(
        JSFunction(nativeMethod: { [weak self] thisValue, args in
          guard let self else { return .undefined }
          guard case .object(let object) = thisValue, let fields = object.headerFields
          else { throw JSError.type("Receiver must be a Headers object") }
          guard case .function(let callback) = args.first else {
            throw JSError.type("Callback must be callable")
          }
          for field in fields {
            _ = try self.callFunction(
              callback, arguments: [.string(field.value), .string(field.name)])
          }
          return .undefined
        }, name: "forEach")))
    publishGlobal("Headers", .function(constructor))
  }

  func makeRequest(url: String, method: String, headers: [(name: String, value: String)],
    body: Data?
  ) -> JSObject {
    let object = JSObject(prototype: requestPrototype)
    object.isFetchRequest = true
    object.requestURL = url
    object.requestMethod = method
    object.requestBody = body
    object.set("url", .string(url))
    object.set("method", .string(method))
    object.set("headers", .object(makeHeaders(headers)))
    return object
  }

  private func installRequestConstructor() {
    let build: ([JSValue]) throws -> JSValue = { [weak self] args in
      guard let self else { return .undefined }
      let parts = try self.requestParts(
        args.first, options: args.count > 1 ? args[1] : .undefined)
      return .object(
        self.makeRequest(
          url: parts.url, method: parts.method, headers: parts.headers, body: parts.body))
    }
    let constructor = JSFunction(native: build, name: "Request")
    constructor.constructNative = build
    constructor.prototypeObject = requestPrototype
    requestPrototype.set("constructor", .function(constructor))
    publishGlobal("Request", .function(constructor))
  }

  private func requestParts(_ input: JSValue?, options: JSValue) throws -> (
    url: String, method: String, headers: [(name: String, value: String)], body: Data?
  ) {
    var url = ""
    var method = "GET"
    var headers: [(name: String, value: String)] = []
    var body: Data?
    if case .object(let object) = input, object.isFetchRequest {
      url = object.requestURL
      method = object.requestMethod
      headers = try headersFrom(object.get("headers"))
      body = object.requestBody
    } else if let input {
      url = try toString(input)
    }
    guard !url.isEmpty else { throw JSError.type("Request URL must not be empty") }
    if case .object(let initObject) = options {
      if case .string(let rawMethod) = initObject.get("method"), !rawMethod.isEmpty {
        method = rawMethod.uppercased()
      }
      if initObject.get("headers").isNullish == false {
        headers = try headersFrom(initObject.get("headers"))
      }
      if initObject.get("body").isNullish == false {
        body = try requestBodyData(initObject.get("body"))
      }
    }
    if (method == "GET" || method == "HEAD") && body != nil {
      throw JSError.type("Request with GET/HEAD method cannot have a body")
    }
    return (url, method, headers, body)
  }

  private func requestBodyData(_ value: JSValue) throws -> Data {
    switch value {
    case .string(let text):
      return Data(text.utf8)
    case .object(let object) where object.isArrayBuffer:
      return object.arrayBufferData ?? Data()
    default:
      return Data(try toString(value).utf8)
    }
  }

  func makeResponse(status: Int, statusText: String, headers: [(name: String, value: String)],
    url: String, body: Data
  ) -> JSObject {
    let object = JSObject(prototype: responsePrototype)
    object.isFetchResponse = true
    object.responseStatus = status
    object.responseStatusText = statusText
    object.responseURL = url
    object.responseBody = body
    object.set("status", .number(Double(status)))
    object.set("statusText", .string(statusText))
    object.set("ok", .bool(status >= 200 && status < 300))
    object.set("url", .string(url))
    object.set("type", .string("basic"))
    object.set("headers", .object(makeHeaders(headers)))
    object.headerFields = headers
    defineDataProperty(
      object, "__bodyUsed", .bool(false), writable: true, enumerable: false,
      configurable: false)
    return object
  }

  private func consumeResponseBody(_ object: JSObject) throws -> Data {
    guard object.isFetchResponse else {
      throw JSError.type("Receiver must be a Response object")
    }
    if case .bool(true) = object.properties["__bodyUsed"] {
      throw JSError.type("Response body has already been used")
    }
    object.properties["__bodyUsed"] = .bool(true)
    return object.responseBody ?? Data()
  }

  private func responseBodyText(_ data: Data) -> String {
    String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
  }

  private func installResponseConstructor() {
    let build: ([JSValue]) throws -> JSValue = { [weak self] args in
      guard let self else { return .undefined }
      var status = 200
      var statusText = "OK"
      var headers: [(name: String, value: String)] = []
      if args.count > 1, case .object(let initObject) = args[1] {
        if case .number(let rawStatus) = initObject.get("status") {
          status = Int(rawStatus)
        }
        if case .string(let rawText) = initObject.get("statusText") {
          statusText = rawText
        }
        if initObject.get("headers").isNullish == false {
          headers = try self.headersFrom(initObject.get("headers"))
        }
      }
      guard status >= 200 && status < 600 else {
        throw JSError.range("Response status must be in the range 200 to 599")
      }
      let hasBody = args.first?.isNullish == false
      if hasBody && (status == 204 || status == 205 || status == 304) {
        throw JSError.type("Response with null body status cannot have a body")
      }
      var body = Data()
      if hasBody {
        body = try self.requestBodyData(args.first ?? .undefined)
      }
      return .object(
        self.makeResponse(
          status: status, statusText: statusText, headers: headers, url: "", body: body))
    }
    let constructor = JSFunction(native: build, name: "Response")
    constructor.constructNative = build
    constructor.prototypeObject = responsePrototype
    responsePrototype.set("constructor", .function(constructor))
    responsePrototype.set(
      "text",
      .function(
        JSFunction(nativeMethod: { [weak self] thisValue, _ in
          guard let self else { return .undefined }
          guard case .object(let object) = thisValue else {
            throw JSError.type("Receiver must be a Response object")
          }
          let data = try self.consumeResponseBody(object)
          let capability = self.newCapability()
          capability.resolve(.string(self.responseBodyText(data)))
          return capability.promise
        }, name: "text")))
    responsePrototype.set(
      "json",
      .function(
        JSFunction(nativeMethod: { [weak self] thisValue, _ in
          guard let self else { return .undefined }
          guard case .object(let object) = thisValue else {
            throw JSError.type("Receiver must be a Response object")
          }
          let data = try self.consumeResponseBody(object)
          let capability = self.newCapability()
          do {
            guard case .object(let json) = self.globals.get("JSON") else {
              throw JSError.runtime("JSON is not available")
            }
            let parsed = try self.callValue(
              json.get("parse"), thisValue: .object(json),
              arguments: [.string(self.responseBodyText(data))])
            capability.resolve(parsed)
          } catch let error as JSError {
            capability.reject(self.errorValue(for: error))
          } catch {
            capability.reject(
              self.constructError(type: "SyntaxError", message: error.localizedDescription))
          }
          return capability.promise
        }, name: "json")))
    responsePrototype.set(
      "arrayBuffer",
      .function(
        JSFunction(nativeMethod: { [weak self] thisValue, _ in
          guard let self else { return .undefined }
          guard case .object(let object) = thisValue else {
            throw JSError.type("Receiver must be a Response object")
          }
          let data = try self.consumeResponseBody(object)
          let buffer = JSObject(prototype: self.arrayBufferPrototype)
          buffer.isArrayBuffer = true
          buffer.arrayBufferData = data
          buffer.set("byteLength", .number(Double(data.count)))
          let capability = self.newCapability()
          capability.resolve(.object(buffer))
          return capability.promise
        }, name: "arrayBuffer")))
    responsePrototype.set(
      "clone",
      .function(
        JSFunction(nativeMethod: { [weak self] thisValue, _ in
          guard let self else { return .undefined }
          guard case .object(let object) = thisValue, object.isFetchResponse else {
            throw JSError.type("Receiver must be a Response object")
          }
          if case .bool(true) = object.properties["__bodyUsed"] {
            throw JSError.type("Response body has already been used")
          }
          return .object(
            self.makeResponse(
              status: object.responseStatus, statusText: object.responseStatusText,
              headers: object.headerFields ?? [],
              url: object.responseURL, body: object.responseBody ?? Data()))
        }, name: "clone")))
    publishGlobal("Response", .function(constructor))
  }

  private static let forbiddenMethods: Set<String> = ["TRACE", "TRACK", "CONNECT"]

  private func installFetchFunction() {
    globals.define(
      "fetch",
      value: .function(
        JSFunction(native: { [weak self] args in
          guard let self else { return .undefined }
          let parts = try self.requestParts(
            args.first, options: args.count > 1 ? args[1] : .undefined)
          guard self.asyncFetch != nil else {
            throw JSError.type("fetch is not available in this context")
          }
          var resolvedURL = parts.url
          if URL(string: resolvedURL)?.scheme == nil,
            let base = self.hostHooks.currentURL?(),
            let baseURL = URL(string: base),
            let absolute = URL(string: parts.url, relativeTo: baseURL)?.absoluteURL
          {
            resolvedURL = absolute.absoluteString
          }
          guard URL(string: resolvedURL)?.scheme != nil else {
            throw JSError.type("fetch URL must be a valid absolute URL")
          }
          if Self.forbiddenMethods.contains(parts.method) {
            throw JSError.type("fetch method \(parts.method) is forbidden")
          }
          let bodyText = parts.body.flatMap { String(data: $0, encoding: .utf8) }
          let capability = self.newCapability()
          let token = self.registerFetchCapability(capability)
          let box = FetchBox(runtime: self)
          let url = resolvedURL
          let method = parts.method
          var headerMap: [String: String] = [:]
          for field in parts.headers {
            if let existing = headerMap[field.name] {
              headerMap[field.name] = existing + ", " + field.value
            } else {
              headerMap[field.name] = field.value
            }
          }
          Task { [box, token, url, method, headerMap, bodyText] in
            let outcome: FetchOutcome
            if let fetch = box.runtime?.asyncFetch {
              do {
                let (status, responseHeaders, data) = try await fetch(
                  url, method, headerMap, bodyText)
                outcome = .ok(
                  status: status, headers: responseHeaders, url: url, body: data)
              } catch {
                outcome = .failure("fetch failed: \(error.localizedDescription)")
              }
            } else {
              outcome = .failure("fetch is not available in this context")
            }
            box.runtime?.enqueueCompletion { [box, token, outcome] in
              guard let runtime = box.runtime,
                let capability = runtime.takeFetchCapability(token)
              else {
                return
              }
              switch outcome {
              case .ok(let status, let responseHeaders, let responseURL, let data):
                var fields = responseHeaders.map { (name: $0.key.lowercased(), value: $0.value) }
                fields.sort { $0.name < $1.name }
                capability.resolve(
                  .object(
                    runtime.makeResponse(
                      status: status, statusText: Self.statusText(for: status),
                      headers: fields, url: responseURL, body: data)))
              case .failure(let message):
                capability.reject(
                  runtime.constructError(type: "TypeError", message: message))
              }
            }
          }
          return capability.promise
        }, name: "fetch")))
  }

  private static func statusText(for status: Int) -> String {
    switch status {
    case 200: return "OK"
    case 201: return "Created"
    case 204: return "No Content"
    case 205: return "Reset Content"
    case 206: return "Partial Content"
    case 301: return "Moved Permanently"
    case 302: return "Found"
    case 303: return "See Other"
    case 304: return "Not Modified"
    case 307: return "Temporary Redirect"
    case 308: return "Permanent Redirect"
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 403: return "Forbidden"
    case 404: return "Not Found"
    case 405: return "Method Not Allowed"
    case 408: return "Request Timeout"
    case 409: return "Conflict"
    case 429: return "Too Many Requests"
    case 500: return "Internal Server Error"
    case 502: return "Bad Gateway"
    case 503: return "Service Unavailable"
    case 504: return "Gateway Timeout"
    default: return ""
    }
  }
}
