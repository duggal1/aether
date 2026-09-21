import DOM
import Foundation

extension JSBuiltins {
  static func primitiveString(_ value: JSValue) throws -> String {
    switch value {
    case .string(let text): return text
    case .object(let object):
      if case .string(let text) = object.get("value") { return text }
      throw JSError.type("Receiver must be a String")
    default:
      throw JSError.type("Receiver must be a String")
    }
  }

  static func installString(into runtime: JSRuntime) {
    let proto = runtime.stringPrototype
    let constructor = makeConstructor(
      runtime: runtime, name: "String",
      call: { [weak runtime] args in
        guard let runtime else { return .undefined }
        if let first = args.first {
          return .string(try runtime.toString(first))
        }
        return .string("")
      },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        let object = JSObject(prototype: runtime.stringPrototype)
        if let first = args.first {
          let text = try runtime.toString(first)
          object.set("value", .string(text))
          object.set("length", .number(Double(text.count)))
        } else {
          object.set("value", .string(""))
          object.set("length", .number(0))
        }
        return .object(object)
      })
    publish(into: runtime, "String", .function(constructor))
    constructor.prototypeObject = runtime.stringPrototype
    runtime.stringPrototype.set("constructor", .function(constructor))
    let statics = constructor.staticProperties
    statics.defineNative("fromCharCode") { _, args in
      var text = ""
      for argument in args {
        if case .number(let number) = argument {
          let unit = UInt16(truncatingIfNeeded: Int(number))
          text.append(Character(UnicodeScalar(unit) ?? UnicodeScalar(0)))
        } else {
          text.append(Character(UnicodeScalar(0)))
        }
      }
      return .string(text)
    }
    statics.defineNative("fromCodePoint") { _, args in
      var text = ""
      for argument in args {
        guard case .number(let number) = argument,
          number >= 0, number <= 1114111, number.rounded() == number,
          let scalar = UnicodeScalar(UInt32(number))
        else {
          throw JSError.range("Invalid code point")
        }
        text.append(Character(scalar))
      }
      return .string(text)
    }
    statics.defineNative("raw") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      guard args.first != nil,
        case .object(let template) = args.first ?? .undefined
      else {
        throw JSError.type("First argument must be a template object")
      }
      let raw: JSValue = template.get("raw")
      guard case .object(let rawObject) = raw else {
        throw JSError.type("Template is missing raw strings")
      }
      let count = Int((try? runtime.toNumber(rawObject.get("length"))) ?? 0)
      var result = ""
      for index in 0..<max(0, count) {
        result += (try? runtime.toString(rawObject.get(String(index)))) ?? ""
        if index + 1 < args.count {
          result += (try? runtime.toString(args[index + 1])) ?? ""
        }
      }
      return .string(result)
    }
    proto.defineNative("charAt") { thisArg, args in
      let text = try primitiveString(thisArg)
      guard case .number(let number) = args.first, !number.isNaN else {
        return .string(String(text.prefix(1)))
      }
      let index = Int(number)
      if index < 0 || index >= text.count { return .string("") }
      return .string(String(text[text.index(text.startIndex, offsetBy: index)]))
    }
    proto.defineNative("at") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      let raw = try runtime.toNumber(args.first ?? .undefined)
      if raw.isNaN { return .undefined }
      var index = Int(raw)
      if index < 0 { index += text.count }
      if index < 0 || index >= text.count { return .undefined }
      return .string(String(text[text.index(text.startIndex, offsetBy: index)]))
    }
    proto.defineNative("charCodeAt") { thisArg, args in
      let text = try primitiveString(thisArg)
      guard case .number(let number) = args.first, !number.isNaN else {
        return text.utf16.first.map { .number(Double($0)) } ?? .number(.nan)
      }
      let index = Int(number)
      let units = Array(text.utf16)
      if index < 0 || index >= units.count { return .number(.nan) }
      return .number(Double(units[index]))
    }
    proto.defineNative("codePointAt") { thisArg, args in
      let text = try primitiveString(thisArg)
      let units = Array(text.utf16)
      var index = 0
      if case .number(let number) = args.first, !number.isNaN { index = Int(number) }
      if index < 0 || index >= units.count { return .undefined }
      let lead = units[index]
      if lead >= 0xD800 && lead <= 0xDBFF, index + 1 < units.count {
        let trail = units[index + 1]
        if trail >= 0xDC00 && trail <= 0xDFFF {
          let value = 0x10000 + (Int(lead - 0xD800) << 10) + Int(trail - 0xDC00)
          return .number(Double(value))
        }
      }
      return .number(Double(lead))
    }
    proto.defineNative("slice") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      let units = Array(text.utf16)
      let length = units.count
      let start = sliceIndex(args.first, length: length, runtime: runtime)
      let end = args.count > 1
        ? sliceIndex(args[1], length: length, runtime: runtime) : length
      if end <= start { return .string("") }
      return .string(jsSubstring(text, utf16Start: start, utf16End: end))
    }
    proto.defineNative("substring") { [weak runtime] thisArg, args in
      guard runtime != nil else { return .undefined }
      let text = try primitiveString(thisArg)
      let units = Array(text.utf16)
      let length = units.count
      func clamp(_ value: JSValue?) -> Int {
        guard let value, case .number(let number) = value, !number.isNaN else { return 0 }
        return min(length, max(0, Int(number)))
      }
      var start = clamp(args.first)
      var end = args.count > 1 ? clamp(args[1]) : length
      if start > end { swap(&start, &end) }
      return .string(jsSubstring(text, utf16Start: start, utf16End: end))
    }
    proto.defineNative("substr") { [weak runtime] thisArg, args in
      guard runtime != nil else { return .undefined }
      let text = try primitiveString(thisArg)
      let units = Array(text.utf16)
      let length = units.count
      var start = 0
      if let first = args.first, case .number(let number) = first, !number.isNaN {
        start = Int(number)
        if start < 0 { start = max(0, length + start) }
      }
      var span = length - start
      if args.count > 1, case .number(let number) = args[1], !number.isNaN {
        span = max(0, min(span, Int(number)))
      }
      if span <= 0 || start >= length { return .string("") }
      return .string(jsSubstring(text, utf16Start: start, utf16End: start + span))
    }
    proto.defineNative("indexOf") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      let needle = try runtime.toString(args.first ?? .undefined)
      var start = 0
      if args.count > 1 {
        let raw = try runtime.toNumber(args[1])
        start = raw.isNaN ? 0 : max(0, Int(raw))
      }
      let units = Array(text.utf16)
      let needleUnits = Array(needle.utf16)
      if needleUnits.isEmpty { return .number(Double(min(start, units.count))) }
      if start + needleUnits.count > units.count { return .number(-1) }
      for index in start...(units.count - needleUnits.count) {
        if Array(units[index..<(index + needleUnits.count)]) == needleUnits {
          return .number(Double(index))
        }
      }
      return .number(-1)
    }
    proto.defineNative("lastIndexOf") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      let needle = try runtime.toString(args.first ?? .undefined)
      let units = Array(text.utf16)
      let needleUnits = Array(needle.utf16)
      var start = units.count
      if args.count > 1 {
        let raw = try runtime.toNumber(args[1])
        start = raw.isNaN ? units.count : max(0, min(units.count, Int(raw)))
      }
      if needleUnits.isEmpty { return .number(Double(min(start, units.count))) }
      if start + needleUnits.count > units.count + needleUnits.count - needleUnits.count {
        start = units.count - needleUnits.count
      }
      if start < 0 { return .number(-1) }
      for index in stride(from: min(start, units.count - needleUnits.count), through: 0, by: -1)
      {
        if Array(units[index..<(index + needleUnits.count)]) == needleUnits {
          return .number(Double(index))
        }
      }
      return .number(-1)
    }
    proto.defineNative("includes") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      let needle = try runtime.toString(args.first ?? .undefined)
      if needle.contains("\u{FFFD}") == false, needle.utf16.count > text.utf16.count + 1 {
        return .bool(false)
      }
      var start = 0
      if args.count > 1 {
        let raw = try runtime.toNumber(args[1])
        start = raw.isNaN ? 0 : max(0, Int(raw))
      }
      let units = Array(text.utf16.dropFirst(min(start, text.utf16.count)))
      let needleUnits = Array(needle.utf16)
      if needleUnits.isEmpty { return .bool(true) }
      if needleUnits.count > units.count { return .bool(false) }
      for index in 0...(units.count - needleUnits.count) {
        if Array(units[index..<(index + needleUnits.count)]) == needleUnits {
          return .bool(true)
        }
      }
      return .bool(false)
    }
    proto.defineNative("startsWith") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      let needle = try runtime.toString(args.first ?? .undefined)
      var start = 0
      if args.count > 1 {
        let raw = try runtime.toNumber(args[1])
        start = raw.isNaN ? 0 : max(0, Int(raw))
      }
      let units = Array(text.utf16)
      let needleUnits = Array(needle.utf16)
      if start + needleUnits.count > units.count { return .bool(false) }
      return .bool(
        Array(units[start..<(start + needleUnits.count)]) == needleUnits)
    }
    proto.defineNative("endsWith") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      let needle = try runtime.toString(args.first ?? .undefined)
      let units = Array(text.utf16)
      var length = units.count
      if args.count > 1 {
        let raw = try runtime.toNumber(args[1])
        length = raw.isNaN ? units.count : max(0, min(units.count, Int(raw)))
      }
      let needleUnits = Array(needle.utf16)
      if needleUnits.count > length { return .bool(false) }
      return .bool(
        Array(units[(length - needleUnits.count)..<length]) == needleUnits)
    }
    proto.defineNative("split") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      var limit = Int.max
      if args.count > 1, case .number(let number) = args[1], !number.isNaN {
        limit = max(0, Int(number))
      }
      if limit == 0 { return .object(runtime.makeArray([])) }
      if args.first == nil || args.first?.isNullish == true {
        return .object(runtime.makeArray([.string(text)]))
      }
      var parts: [String]
      if case .object(let object) = args.first,
        case .string(let pattern) = object.get("source")
      {
        let flags = (try? stringValue(object.get("flags"))) ?? ""
        parts = splitRegex(
          runtime: runtime, text: text, pattern: pattern, flags: flags)
      } else {
        let separator = try runtime.toString(args.first ?? .undefined)
        if separator.isEmpty {
          parts = text.map { String($0) }
        } else {
          parts = text.components(separatedBy: separator)
        }
      }
      if parts.count > limit { parts = Array(parts.prefix(limit)) }
      return .object(runtime.makeArray(parts.map { .string($0) }))
    }
    proto.defineNative("trim") { thisArg, _ in
      .string(try primitiveString(thisArg).trimmingCharacters(in: jsTrimmable))
    }
    proto.defineNative("trimStart") { thisArg, _ in
      var text = try primitiveString(thisArg)
      while let first = text.unicodeScalars.first, jsTrimmable.contains(first) {
        text.unicodeScalars.removeFirst()
      }
      return .string(text)
    }
    proto.defineNative("trimEnd") { thisArg, _ in
      var text = try primitiveString(thisArg)
      while let last = text.unicodeScalars.last, jsTrimmable.contains(last) {
        text.unicodeScalars.removeLast()
      }
      return .string(text)
    }
    proto.defineNative("trimLeft") { thisArg, _ in
      var text = try primitiveString(thisArg)
      while let first = text.unicodeScalars.first, jsTrimmable.contains(first) {
        text.unicodeScalars.removeFirst()
      }
      return .string(text)
    }
    proto.defineNative("trimRight") { thisArg, _ in
      var text = try primitiveString(thisArg)
      while let last = text.unicodeScalars.last, jsTrimmable.contains(last) {
        text.unicodeScalars.removeLast()
      }
      return .string(text)
    }
    proto.defineNative("toUpperCase") { thisArg, _ in
      .string(try primitiveString(thisArg).uppercased())
    }
    proto.defineNative("toLowerCase") { thisArg, _ in
      .string(try primitiveString(thisArg).lowercased())
    }
    proto.defineNative("toLocaleUpperCase") { thisArg, _ in
      .string(try primitiveString(thisArg).uppercased(with: Locale.current))
    }
    proto.defineNative("toLocaleLowerCase") { thisArg, _ in
      .string(try primitiveString(thisArg).lowercased(with: Locale.current))
    }
    proto.defineNative("concat") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      var result = try primitiveString(thisArg)
      for argument in args {
        result += try runtime.toString(argument)
      }
      return .string(result)
    }
    proto.defineNative("repeat") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      let raw = try runtime.toNumber(args.first ?? .undefined)
      if raw.isNaN || raw < 0 || raw.isInfinite {
        throw JSError.range("Invalid repeat count")
      }
      return .string(String(repeating: text, count: Int(raw)))
    }
    proto.defineNative("padStart") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      let raw = try runtime.toNumber(args.first ?? .undefined)
      if raw.isNaN { return .string(text) }
      let target = Int(raw)
      if target <= text.count { return .string(text) }
      var fill = " "
      if args.count > 1 {
        fill = try runtime.toString(args[1])
        if fill.isEmpty { return .string(text) }
      }
      var padding = ""
      while padding.count < target - text.count { padding += fill }
      return .string(String(padding.prefix(target - text.count)) + text)
    }
    proto.defineNative("padEnd") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      let raw = try runtime.toNumber(args.first ?? .undefined)
      if raw.isNaN { return .string(text) }
      let target = Int(raw)
      if target <= text.count { return .string(text) }
      var fill = " "
      if args.count > 1 {
        fill = try runtime.toString(args[1])
        if fill.isEmpty { return .string(text) }
      }
      var padding = ""
      while padding.count < target - text.count { padding += fill }
      return .string(text + String(padding.prefix(target - text.count)))
    }
    proto.defineNative("replace") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      let replacement = args.count > 1 ? args[1] : .undefined
      if case .object(let object) = args.first,
        case .string(let pattern) = object.get("source")
      {
        let flags = (try? stringValue(object.get("flags"))) ?? ""
        return .string(try replaceRegex(
          runtime: runtime, text: text, pattern: pattern, flags: flags,
          replacement: replacement, all: flags.contains("g")))
      }
      let needle = try runtime.toString(args.first ?? .undefined)
      let resolved = try replacementText(
        runtime: runtime, replacement: replacement, match: needle, offset: 0,
        input: text, groups: [])
      if needle.isEmpty {
        return .string(resolved + text)
      }
      guard let range = text.range(of: needle) else { return .string(text) }
      return .string(text.replacingCharacters(in: range, with: resolved))
    }
    proto.defineNative("replaceAll") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      let replacement = args.count > 1 ? args[1] : .undefined
      if case .object(let object) = args.first,
        case .string(let pattern) = object.get("source")
      {
        let flags = (try? stringValue(object.get("flags"))) ?? ""
        if !flags.contains("g") {
          throw JSError.type("replaceAll requires a global regex")
        }
        return .string(try replaceRegex(
          runtime: runtime, text: text, pattern: pattern, flags: flags,
          replacement: replacement, all: true))
      }
      let needle = try runtime.toString(args.first ?? .undefined)
      if needle.isEmpty {
        var result = ""
        for (offset, character) in text.enumerated() {
          let piece = try replacementText(
            runtime: runtime, replacement: replacement, match: "", offset: offset,
            input: text, groups: [])
          result += piece
          result.append(character)
        }
        let tail = try replacementText(
          runtime: runtime, replacement: replacement, match: "", offset: text.count,
          input: text, groups: [])
        return .string(result + tail)
      }
      var result = ""
      var remainder = text[...]
      while let range = remainder.range(of: needle) {
        result += remainder[..<range.lowerBound]
        let offset = text.distance(from: text.startIndex, to: range.lowerBound)
        result += try replacementText(
          runtime: runtime, replacement: replacement, match: needle, offset: offset,
          input: text, groups: [])
        remainder = remainder[range.upperBound...]
      }
      result += remainder
      return .string(result)
    }
    proto.defineNative("match") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      guard case .object(let object) = args.first,
        case .string(let pattern) = object.get("source")
      else {
        let needle = try runtime.toString(args.first ?? .undefined)
        guard let range = text.range(of: needle) else { return .null }
        let result = runtime.makeArray([.string(String(text[range]))])
        result.set("index", .number(Double(text.distance(
          from: text.startIndex, to: range.lowerBound))))
        result.set("input", .string(text))
        return .object(result)
      }
      let flags = (try? stringValue(object.get("flags"))) ?? ""
      let compiled = jsCompileRegex(pattern: pattern, flags: flags)
      if let error = compiled.error { throw JSError.syntax(error) }
      if flags.contains("g") {
        var matches: [JSValue] = []
        var cursor = 0
        while matches.count < 1048576 {
          guard let match = jsRegexExec(
            compiled: compiled, input: text, lastIndex: cursor)
          else {
            break
          }
          if let range = match.ranges.first, range.location != NSNotFound {
            matches.append(.string(jsSubstring(
              text, utf16Start: range.location,
              utf16End: range.location + range.length)))
          }
          cursor = match.endUTF16
          if match.ranges.first?.length == 0 { cursor += 1 }
          if cursor > text.utf16.count { break }
        }
        if matches.isEmpty { return .null }
        return .object(runtime.makeArray(matches))
      }
      guard let match = jsRegexExec(compiled: compiled, input: text, lastIndex: 0) else {
        return .null
      }
      return .object(regexResult(
        runtime: runtime, ranges: match.ranges, input: text))
    }
    proto.defineNative("matchAll") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      guard case .object(let object) = args.first,
        case .string(let pattern) = object.get("source")
      else {
        throw JSError.type("Argument must be a global regex")
      }
      let flags = (try? stringValue(object.get("flags"))) ?? ""
      if !flags.contains("g") {
        throw JSError.type("matchAll requires a global regex")
      }
      let compiled = jsCompileRegex(pattern: pattern, flags: flags)
      if let error = compiled.error { throw JSError.syntax(error) }
      var records: [JSValue] = []
      var cursor = 0
      while records.count < 1048576 {
        guard let match = jsRegexExec(
          compiled: compiled, input: text, lastIndex: cursor)
        else {
          break
        }
        records.append(.object(regexResult(
          runtime: runtime, ranges: match.ranges, input: text)))
        cursor = match.endUTF16
        if match.ranges.first?.length == 0 { cursor += 1 }
        if cursor > text.utf16.count { break }
      }
      return .object(makeIterator(runtime: runtime, values: records, asEntries: false))
    }
    proto.defineNative("search") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      let text = try primitiveString(thisArg)
      guard case .object(let object) = args.first,
        case .string(let pattern) = object.get("source")
      else {
        let needle = try runtime.toString(args.first ?? .undefined)
        if let range = text.range(of: needle) {
          return .number(Double(text.distance(from: text.startIndex, to: range.lowerBound)))
        }
        return .number(-1)
      }
      let flags = (try? stringValue(object.get("flags"))) ?? ""
      let compiled = jsCompileRegex(pattern: pattern, flags: flags)
      if let error = compiled.error { throw JSError.syntax(error) }
      guard let match = jsRegexExec(compiled: compiled, input: text, lastIndex: 0),
        let range = match.ranges.first, range.location != NSNotFound
      else {
        return .number(-1)
      }
      return .number(Double(range.location))
    }
  }

  static func stringValue(_ value: JSValue) throws -> String {
    if case .string(let text) = value { return text }
    throw JSError.type("Expected string")
  }

  static func sliceIndex(_ value: JSValue?, length: Int, runtime: JSRuntime) -> Int {
    guard let value, case .number(let number) = value, !number.isNaN else {
      return value == nil ? 0 : 0
    }
    var index = Int(number)
    if index < 0 { index = max(0, length + index) }
    return min(length, index)
  }

  static func splitRegex(
    runtime: JSRuntime, text: String, pattern: String, flags: String
  ) -> [String] {
    let compiled = jsCompileRegex(pattern: pattern, flags: flags + "g")
    guard compiled.error == nil else { return [text] }
    var parts: [String] = []
    var cursor = 0
    while parts.count < 1048576 {
      guard let match = jsRegexExec(
        compiled: compiled, input: text, lastIndex: cursor),
        let range = match.ranges.first, range.location != NSNotFound
      else {
        break
      }
      parts.append(jsSubstring(text, utf16Start: cursor, utf16End: range.location))
      if match.ranges.count > 1 {
        for group in match.ranges.dropFirst() {
          if group.location == NSNotFound {
            parts.append("")
          } else {
            parts.append(jsSubstring(
              text, utf16Start: group.location,
              utf16End: group.location + group.length))
          }
        }
      }
      cursor = match.endUTF16
      if range.length == 0 { cursor += 1 }
      if cursor > text.utf16.count { break }
    }
    parts.append(jsSubstring(
      text, utf16Start: cursor, utf16End: text.utf16.count))
    return parts
  }

  static func replaceRegex(
    runtime: JSRuntime, text: String, pattern: String, flags: String,
    replacement: JSValue, all: Bool
  ) throws -> String {
    let compiled = jsCompileRegex(pattern: pattern, flags: flags)
    if let error = compiled.error { throw JSError.syntax(error) }
    var result = ""
    var cursor = 0
    var count = 0
    while all || count == 0 {
      guard let match = jsRegexExec(
        compiled: compiled, input: text, lastIndex: cursor),
        let range = match.ranges.first, range.location != NSNotFound
      else {
        break
      }
      count += 1
      result += jsSubstring(text, utf16Start: cursor, utf16End: range.location)
      var groups: [String] = []
      for group in match.ranges.dropFirst() {
        if group.location == NSNotFound {
          groups.append("")
        } else {
          groups.append(jsSubstring(
            text, utf16Start: group.location,
            utf16End: group.location + group.length))
        }
      }
      let matched = jsSubstring(
        text, utf16Start: range.location,
        utf16End: range.location + range.length)
      result += try replacementText(
        runtime: runtime, replacement: replacement, match: matched,
        offset: range.location, input: text, groups: groups)
      cursor = match.endUTF16
      if range.length == 0 { cursor += 1 }
      if cursor > text.utf16.count { break }
      if !all { break }
    }
    result += jsSubstring(text, utf16Start: cursor, utf16End: text.utf16.count)
    return result
  }

  static func replacementText(
    runtime: JSRuntime, replacement: JSValue, match: String, offset: Int,
    input: String, groups: [String]
  ) throws -> String {
    if case .function = replacement {
      var args: [JSValue] = [.string(match)]
      args.append(contentsOf: groups.map { .string($0) })
      args.append(.number(Double(offset)))
      args.append(.string(input))
      return try runtime.toString(
        try runtime.callValue(replacement, thisValue: .undefined, arguments: args))
    }
    let template = try runtime.toString(replacement)
    var result = ""
    var index = template.startIndex
    while index < template.endIndex {
      let character = template[index]
      if character == "$" {
        let next = template.index(after: index)
        if next < template.endIndex {
          let marker = template[next]
          switch marker {
          case "$":
            result.append("$")
            index = template.index(after: next)
            continue
          case "&":
            result += match
            index = template.index(after: next)
            continue
          case "`":
            result += jsSubstring(input, utf16Start: 0, utf16End: offset)
            index = template.index(after: next)
            continue
          case "'":
            result += jsSubstring(
              input, utf16Start: offset + match.utf16.count,
              utf16End: input.utf16.count)
            index = template.index(after: next)
            continue
          default:
            if marker.isNumber {
              var digits = String(marker)
              var cursor = template.index(after: next)
              if cursor < template.endIndex, template[cursor].isNumber {
                digits.append(template[cursor])
                cursor = template.index(after: cursor)
              }
              if let position = Int(digits), position >= 1,
                position <= groups.count
              {
                result += groups[position - 1]
              } else if digits == "0" || (Int(digits) ?? 99) > groups.count {
                result += "$" + digits
              }
              index = cursor
              continue
            }
            result.append(character)
            index = next
            continue
          }
        }
      }
      result.append(character)
      index = template.index(after: index)
    }
    return result
  }

  static var jsTrimmable: CharacterSet {
    CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
  }
}
