import DOM
import EngineCore
import Foundation

enum JSMediaElement {
  private struct MediaBox: @unchecked Sendable {
    weak var runtime: JSRuntime?
    var capability: JSPromiseCapability?
  }
  static func isMedia(_ id: NodeID, context: JSDOMContext) -> Bool {
    guard let tag = context.document.node(id)?.tagName?.lowercased() else { return false }
    return tag == "video" || tag == "audio"
  }

  static func property(_ id: NodeID, context: JSDOMContext, name: String) -> JSValue? {
    guard isMedia(id, context: context), let host = context.runtime?.mediaHost ?? context.mediaHost else { return nil }
    let snap = host.mediaSnapshot(node: id)
    switch name {
    case "currentTime", "duration", "volume", "playbackRate":
      if case .number(let value) = snap[name] { return .number(value) }
      return .number(.nan)
    case "paused", "muted", "ended", "seeking", "loop":
      if case .bool(let value) = snap[name] { return .bool(value) }
      return .bool(name == "paused")
    case "readyState", "networkState", "videoWidth", "videoHeight":
      if case .number(let value) = snap[name] { return .number(value) }
      return .number(0)
    case "currentSrc", "src":
      if case .string(let value) = snap[name] { return .string(value) }
      return .string("")
    case "error":
      if let error = snap["error"] { return error }
      return .null
    default:
      return nil
    }
  }

  static func setProperty(
    _ id: NodeID, context: JSDOMContext, name: String, value: JSValue
  ) -> Bool {
    guard isMedia(id, context: context), let host = context.runtime?.mediaHost ?? context.mediaHost else { return false }
    switch name {
    case "currentTime", "volume", "muted", "playbackRate":
      host.mediaSet(node: id, name: name, value: value)
      return true
    default:
      return false
    }
  }

  static func installExtras(_ object: JSObject, id: NodeID, context: JSDOMContext) {
    guard isMedia(id, context: context) else { return }
    object.defineNative("play") { _ in
      guard let runtime = context.runtime, let host = runtime.mediaHost ?? context.mediaHost else {
        throw JSError.type("Media is not available in this context")
      }
      let box = MediaBox(runtime: runtime, capability: runtime.newCapability())
      host.mediaPlay(node: id) { ok, message in
        box.runtime?.enqueueCompletion { [box] in
          if ok { box.capability?.resolve(.undefined) }
          else {
            box.capability?.reject(
              box.runtime?.constructError(
                type: "NotSupportedError", message: message ?? "play failed") ?? .undefined)
          }
        }
      }
      guard let promise = box.capability?.promise else { return .undefined }
      return promise
    }
    object.defineNative("pause") { _ in
      (context.runtime?.mediaHost ?? context.mediaHost)?.mediaPause(node: id)
      return .undefined
    }
    object.defineNative("load") { _ in
      (context.runtime?.mediaHost ?? context.mediaHost)?.mediaSet(node: id, name: "load", value: .undefined)
      return .undefined
    }
    object.defineNative("canPlayType") { args in
      guard let host = context.runtime?.mediaHost ?? context.mediaHost else { return .string("") }
      guard case .string(let mime) = args.first else { return .string("") }
      return .string(host.mediaCanPlayType(node: id, mime: mime))
    }
    object.defineNative("fastSeek") { args in
      guard let runtime = context.runtime, let host = runtime.mediaHost ?? context.mediaHost,
        case .number(let seconds) = args.first
      else { return .undefined }
      let box = MediaBox(runtime: runtime, capability: runtime.newCapability())
      host.mediaSeek(node: id, seconds: seconds) { ok in
        box.runtime?.enqueueCompletion { [box] in
          if ok { box.capability?.resolve(.undefined) }
          else {
            box.capability?.reject(
              box.runtime?.constructError(type: "NotSupportedError", message: "seek failed")
                ?? .undefined)
          }
        }
      }
      guard let promise = box.capability?.promise else { return .undefined }
      return promise
    }
  }
}
