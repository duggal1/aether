import DOM
import Foundation

extension JSBuiltins {
  static func installTextCodec(into runtime: JSRuntime) {
    let encoderConstructor = makeConstructor(
      runtime: runtime, name: "TextEncoder",
      call: { _ in throw JSError.type("TextEncoder must be constructed") },
      construct: { [weak runtime] _ in
        guard let runtime else { return .undefined }
        let object = JSObject(prototype: runtime.objectPrototype)
        object.set("encoding", .string("utf-8"))
        return .object(object)
      })
    encoderConstructor.staticProperties.defineNative("encode") { _, _ in .undefined }
    let encoderProto = JSObject(prototype: runtime.objectPrototype)
    encoderConstructor.prototypeObject = encoderProto
    encoderProto.set("constructor", .function(encoderConstructor))
    encoderProto.defineNative("encode") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      let text = try runtime.toString(args.first ?? .undefined)
      let data = Data(text.utf8)
      let buffer = JSObject(prototype: runtime.arrayBufferPrototype)
      buffer.isArrayBuffer = true
      buffer.arrayBufferData = data
      buffer.set("byteLength", .number(Double(data.count)))
      return .object(makeTypedArrayView(
        runtime: runtime, kind: "uint8", bytes: 1, buffer: buffer, offset: 0,
        count: data.count))
    }
    encoderProto.defineNative("encodeInto") { [weak runtime] _, args in
      guard let runtime else { return .undefined }
      let text = try runtime.toString(args.first ?? .undefined)
      guard args.count > 1, case .object(let view) = args[1],
        view.typedArrayKind != nil
      else {
        throw JSError.type("Target must be a typed array")
      }
      let bytes = Array(text.utf8)
      let count = min(bytes.count, view.typedArrayLength)
      for index in 0..<count {
        try writeTypedElement(
          runtime: runtime, view: view, index: index, value: .number(Double(bytes[index])))
      }
      let result = JSObject(prototype: runtime.objectPrototype)
      result.set("read", .number(Double(text.count)))
      result.set("written", .number(Double(count)))
      return .object(result)
    }
    publish(into: runtime, "TextEncoder", .function(encoderConstructor))

    let decoderConstructor = makeConstructor(
      runtime: runtime, name: "TextDecoder",
      call: { _ in throw JSError.type("TextDecoder must be constructed") },
      construct: { [weak runtime] args in
        guard let runtime else { return .undefined }
        let label = args.first.map { (try? runtime.toString($0)) ?? "utf-8" } ?? "utf-8"
        let normalized = label.lowercased().replacingOccurrences(of: "_", with: "-")
        let supported = [
          "utf-8", "utf8", "utf-16le", "utf-16be", "utf-16", "latin1", "iso-8859-1",
          "windows-1252", "ascii",
        ]
        if !supported.contains(normalized) {
          throw JSError.range("Unsupported encoding \(label)")
        }
        var fatal = false
        var ignoreBOM = false
        if args.count > 1, case .object(let options) = args[1] {
          fatal = options.get("fatal").truthy
          ignoreBOM = options.get("ignoreBOM").truthy
        }
        let object = JSObject(prototype: runtime.objectPrototype)
        object.set("encoding", .string(normalized == "utf8" ? "utf-8" : normalized))
        object.set("fatal", .bool(fatal))
        object.set("ignoreBOM", .bool(ignoreBOM))
        return .object(object)
      })
    let decoderProto = JSObject(prototype: runtime.objectPrototype)
    decoderConstructor.prototypeObject = decoderProto
    decoderProto.set("constructor", .function(decoderConstructor))
    decoderProto.defineNative("decode") { [weak runtime] thisArg, args in
      guard let runtime else { return .undefined }
      guard case .object(let decoder) = thisArg,
        case .string(let encoding) = decoder.get("encoding")
      else {
        throw JSError.type("Receiver must be a TextDecoder")
      }
      let fatal = decoder.get("fatal").truthy
      let ignoreBOM = decoder.get("ignoreBOM").truthy
      var bytes = Data()
      if let first = args.first, !first.isNullish {
        if case .object(let view) = first, let kind = view.typedArrayKind {
          if kind == "dataview" {
            if let buffer = view.typedArrayBuffer,
              let data = buffer.arrayBufferData
            {
              let range = view.typedArrayOffset..<(view.typedArrayOffset + view.typedArrayLength)
              bytes = data.subdata(in: range)
            }
          } else {
            let elementBytes = elementBytes(kind: kind)
            if let buffer = view.typedArrayBuffer,
              let data = buffer.arrayBufferData
            {
              let range = view.typedArrayOffset..<(view.typedArrayOffset
                + view.typedArrayLength * elementBytes)
              bytes = data.subdata(in: range)
            }
          }
        } else if case .object(let buffer) = first, buffer.isArrayBuffer {
          bytes = buffer.arrayBufferData ?? Data()
        } else {
          throw JSError.type("Input must be a buffer view")
        }
      }
      var payload = bytes
      if !ignoreBOM, payload.starts(with: [0xEF, 0xBB, 0xBF]) {
        payload = payload.dropFirst(3)
      }
      switch encoding {
      case "utf-8", "utf8", "ascii":
        if let text = String(data: payload, encoding: .utf8) {
          return .string(text)
        }
        if fatal { throw JSError.type("Invalid byte sequence") }
        return .string(String(decoding: payload, as: UTF8.self))
      case "utf-16le", "utf-16":
        if let text = String(data: payload, encoding: .utf16LittleEndian) {
          return .string(text)
        }
        throw JSError.type("Invalid byte sequence")
      case "utf-16be":
        if let text = String(data: payload, encoding: .utf16BigEndian) {
          return .string(text)
        }
        throw JSError.type("Invalid byte sequence")
      default:
        if let text = String(data: payload, encoding: .isoLatin1) {
          return .string(text)
        }
        throw JSError.type("Invalid byte sequence")
      }
    }
    publish(into: runtime, "TextDecoder", .function(decoderConstructor))

    let atobFunction = JSFunction(native: { [weak runtime] args in
      guard let runtime else { return .undefined }
      let text = try runtime.toString(args.first ?? .undefined)
      let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters) else {
        throw JSError.type("Invalid base64 string")
      }
      return .string(String(data: data, encoding: .isoLatin1) ?? "")
    }, name: "atob")
    publish(into: runtime, "atob", .function(atobFunction))
    let btoaFunction = JSFunction(native: { [weak runtime] args in
      guard let runtime else { return .undefined }
      let text = try runtime.toString(args.first ?? .undefined)
      var bytes: [UInt8] = []
      for scalar in text.unicodeScalars {
        guard scalar.value <= 0xFF else {
          throw JSError.type("String contains non-Latin1 characters")
        }
        bytes.append(UInt8(scalar.value))
      }
      return .string(Data(bytes).base64EncodedString())
    }, name: "btoa")
    publish(into: runtime, "btoa", .function(btoaFunction))
  }
}
