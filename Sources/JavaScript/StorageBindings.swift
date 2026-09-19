import Foundation
import Storage

public enum JSStorageBindings {
  public static func localStorageObject(_ storage: LocalStorage) -> JSObject {
    let object = JSObject(nativeGet: { key in
      if key == "length" { return .number(Double(storage.count)) }
      return nil
    })
    object.set(
      "getItem",
      .function(
        JSFunction(native: { args in
          guard case .string(let key) = args.first else { return .null }
          return storage.get(key).map(JSValue.string) ?? .null
        })))
    object.set(
      "setItem",
      .function(
        JSFunction(native: { args in
          guard args.count > 1 else { return .undefined }
          storage.set(args[0].description, value: args[1].description)
          return .undefined
        })))
    object.set(
      "removeItem",
      .function(
        JSFunction(native: { args in
          guard let first = args.first else { return .undefined }
          storage.remove(first.description)
          return .undefined
        })))
    object.set(
      "clear",
      .function(
        JSFunction(native: { _ in
          storage.clear()
          return .undefined
        })))
    object.set(
      "key",
      .function(
        JSFunction(native: { args in
          guard case .number(let index) = args.first, index >= 0 else { return .null }
          let keys = storage.snapshot().keys.sorted()
          let offset = Int(index)
          guard keys.indices.contains(offset) else { return .null }
          return .string(keys[offset])
        })))
    return object
  }
}
