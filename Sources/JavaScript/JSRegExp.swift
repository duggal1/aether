import DOM
import Foundation

struct JSCompiledRegex {
  var pattern: String
  var flags: String
  var expression: NSRegularExpression?
  var error: String?

  var global: Bool { flags.contains("g") }
  var ignoreCase: Bool { flags.contains("i") }
  var multiline: Bool { flags.contains("m") }
  var dotAll: Bool { flags.contains("s") }
  var sticky: Bool { flags.contains("y") }
}

func jsCompileRegex(pattern: String, flags: String) -> JSCompiledRegex {
  var unsupported: [String] = []
  for flag in flags {
    if !"gimsuy".contains(flag) { unsupported.append(String(flag)) }
  }
  if !unsupported.isEmpty {
    return JSCompiledRegex(
      pattern: pattern, flags: flags, expression: nil,
      error: "Unsupported regex flags")
  }
  let translated = jsTranslatePattern(pattern, dotAll: flags.contains("s"))
  var options: NSRegularExpression.Options = []
  if flags.contains("i") { options.insert(.caseInsensitive) }
  if flags.contains("m") { options.insert(.anchorsMatchLines) }
  if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }
  do {
    let expression = try NSRegularExpression(pattern: translated, options: options)
    return JSCompiledRegex(
      pattern: pattern, flags: flags, expression: expression, error: nil)
  } catch {
    return JSCompiledRegex(
      pattern: pattern, flags: flags, expression: nil, error: "Invalid regex")
  }
}

func jsTranslatePattern(_ pattern: String, dotAll: Bool) -> String {
  guard dotAll else { return pattern }
  var result = ""
  var inClass = false
  var index = pattern.startIndex
  while index < pattern.endIndex {
    let character = pattern[index]
    if character == "\\" {
      result.append(character)
      index = pattern.index(after: index)
      if index < pattern.endIndex {
        result.append(pattern[index])
        index = pattern.index(after: index)
      }
      continue
    }
    if character == "[" { inClass = true }
    if character == "]" { inClass = false }
    if character == ".", !inClass {
      result += "[\\s\\S]"
    } else {
      result.append(character)
    }
    index = pattern.index(after: index)
  }
  return result
}

struct JSRegexMatch {
  var ranges: [NSRange]
  var endUTF16: Int
}

func jsRegexExec(
  compiled: JSCompiledRegex, input: String, lastIndex: Int
) -> JSRegexMatch? {
  guard let expression = compiled.expression else { return nil }
  let utf16 = input.utf16
  let total = utf16.count
  let start = max(0, min(lastIndex, total))
  let searchRange = NSRange(location: start, length: total - start)
  if compiled.sticky {
    guard let match = expression.firstMatch(
      in: input, options: [.anchored], range: searchRange)
    else {
      return nil
    }
    return JSRegexMatch(
      ranges: (0..<match.numberOfRanges).map { match.range(at: $0) },
      endUTF16: match.range.upperBound)
  }
  guard let match = expression.firstMatch(in: input, options: [], range: searchRange) else {
    return nil
  }
  return JSRegexMatch(
    ranges: (0..<match.numberOfRanges).map { match.range(at: $0) },
    endUTF16: match.range.upperBound)
}

func jsSubstring(_ input: String, utf16Start: Int, utf16End: Int) -> String {
  let utf16 = input.utf16
  guard utf16Start <= utf16End, utf16End <= utf16.count else { return "" }
  let start = utf16.index(utf16.startIndex, offsetBy: utf16Start)
  let end = utf16.index(utf16.startIndex, offsetBy: utf16End)
  if let startIndex = start.samePosition(in: input),
    let endIndex = end.samePosition(in: input)
  {
    return String(input[startIndex..<endIndex])
  }
  return ""
}

extension JSBuiltins {
  static func installRegExp(into runtime: JSRuntime) {
    let proto = runtime.regexpPrototype
    proto.defineNative("exec") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg,
        case .string(let pattern) = object.get("source")
      else {
        throw JSError.type("Receiver must be a RegExp")
      }
      let flags: String
      if case .string(let text) = object.get("flags") { flags = text } else { flags = "" }
      let input = try runtime.toString(args.first ?? .undefined)
      var lastIndex = 0
      if case .number(let number) = object.get("lastIndex") {
        lastIndex = max(0, Int(number))
      }
      let compiled = jsCompileRegex(pattern: pattern, flags: flags)
      if let error = compiled.error { throw JSError.syntax(error) }
      guard let match = jsRegexExec(
        compiled: compiled, input: input, lastIndex: compiled.global || compiled.sticky ? lastIndex : 0)
      else {
        if compiled.global || compiled.sticky { object.set("lastIndex", .number(0)) }
        return .null
      }
      if compiled.global || compiled.sticky {
        object.set("lastIndex", .number(Double(match.endUTF16)))
      }
      return .object(regexResult(
        runtime: runtime, ranges: match.ranges, input: input))
    }
    proto.defineNative("test") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let object) = thisArg else {
        throw JSError.type("Receiver must be a RegExp")
      }
      let method = runtime.runtimeRead(object, "exec")
      let result = try runtime.callValue(
        method, thisValue: thisArg, arguments: [args.first ?? .undefined])
      if case .null = result { return .bool(false) }
      return .bool(true)
    }
    proto.defineNative("toString") { thisArg, _ in
      guard case .object(let object) = thisArg,
        case .string(let pattern) = object.get("source")
      else {
        throw JSError.type("Receiver must be a RegExp")
      }
      let flags: String
      if case .string(let text) = object.get("flags") { flags = text } else { flags = "" }
      return .string("/\(pattern)/\(flags)")
    }
    let constructor = makeConstructor(
      runtime: runtime, name: "RegExp",
      call: { [weak runtime] args in
        guard let runtime else { return .undefined }
        return try buildRegExp(runtime: runtime, args: args)
      },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        return try buildRegExp(runtime: runtime, args: args)
      })
    publish(into: runtime, "RegExp", .function(constructor))
    constructor.prototypeObject = runtime.regexpPrototype
    runtime.regexpPrototype.set("constructor", .function(constructor))
    runtime.regexpConstructor = constructor
  }

  static func buildRegExp(runtime: JSRuntime, args: [JSValue]) throws -> JSValue {
    if case .object(let source) = args.first,
      case .string = source.get("source")
    {
      if args.count > 1, !args[1].isNullish {
        throw JSError.type("Cannot supply flags when constructing from RegExp")
      }
      let object = JSObject(prototype: runtime.regexpPrototype)
      object.set("source", source.get("source"))
      object.set("flags", source.get("flags"))
      object.set("lastIndex", .number(0))
      syncRegExpFlags(runtime: runtime, object: object)
      return .object(object)
    }
    var text = "(?:)"
    if let first = args.first {
      text = (try? runtime.toString(first)) ?? "(?:)"
    }
    let flags = args.count > 1 ? try runtime.toString(args[1]) : ""
    let compiled = jsCompileRegex(pattern: text, flags: flags)
    if let error = compiled.error { throw JSError.syntax(error) }
    if compiled.expression == nil { throw JSError.syntax("Invalid regex") }
    let object = JSObject(prototype: runtime.regexpPrototype)
    object.set("source", .string(text))
    object.set("flags", .string(normalizeRegExpFlags(flags)))
    object.set("lastIndex", .number(0))
    syncRegExpFlags(runtime: runtime, object: object)
    return .object(object)
  }

  static func normalizeRegExpFlags(_ flags: String) -> String {
    let order = ["d", "g", "i", "m", "s", "u", "v", "y"]
    var seen = Set<Character>()
    var result = ""
    for flag in order {
      let character = Character(flag)
      if flags.contains(character), !seen.contains(character) {
        seen.insert(character)
        result.append(character)
      }
    }
    return result
  }

  static func syncRegExpFlags(runtime: JSRuntime, object: JSObject) {
    let flags: String
    if case .string(let text) = object.get("flags") { flags = text } else { flags = "" }
    object.set("global", .bool(flags.contains("g")))
    object.set("ignoreCase", .bool(flags.contains("i")))
    object.set("multiline", .bool(flags.contains("m")))
    object.set("dotAll", .bool(flags.contains("s")))
    object.set("sticky", .bool(flags.contains("y")))
    object.set("unicode", .bool(flags.contains("u")))
    _ = runtime
  }

  static func regexResult(
    runtime: JSRuntime, ranges: [NSRange], input: String
  ) -> JSObject {
    let object = runtime.makeArray([])
    for (index, range) in ranges.enumerated() {
      if range.location == NSNotFound {
        object.properties[String(index)] = .undefined
      } else {
        object.properties[String(index)] = .string(
          jsSubstring(input, utf16Start: range.location,
            utf16End: range.location + range.length))
      }
    }
    object.properties["length"] = .number(Double(ranges.count))
    if let first = ranges.first, first.location != NSNotFound {
      object.set("index", .number(Double(first.location)))
    } else {
      object.set("index", .number(0))
    }
    object.set("input", .string(input))
    return object
  }
}
