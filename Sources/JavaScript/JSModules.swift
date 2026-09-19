import Foundation

public final class JSModuleRecord {
  public var path: String?
  public var source: String?
  public var exports: [String: JSValue] = [:]
  public var evaluated = false

  public init(path: String? = nil) {
    self.path = path
  }
}

public final class JSModuleRegistry {
  private var sources: [String: String] = [:]
  private var cache: [String: JSModuleRecord] = [:]

  public init() {}

  public func register(path: String, source: String) {
    sources[path] = source
    cache.removeValue(forKey: path)
  }

  public func record(for path: String) -> JSModuleRecord {
    if let cached = cache[path] { return cached }
    let record = JSModuleRecord(path: path)
    cache[path] = record
    return record
  }

  public func load(path: String, relativeTo base: String?, runtime: JSRuntime) throws
    -> JSModuleRecord
  {
    let resolved = resolve(path, relativeTo: base)
    if let cached = cache[resolved] {
      if cached.evaluated { return cached }
      if cached.source != nil { return cached }
    }
    guard let source = sources[resolved] ?? sources[path] else {
      throw JSError.runtime("Cannot find module \(path)")
    }
    let record = JSModuleRecord(path: resolved)
    record.source = source
    cache[resolved] = record
    try runtime.evaluateModuleRecord(source, record: record)
    record.evaluated = true
    return record
  }

  private func resolve(_ path: String, relativeTo base: String?) -> String {
    guard let base, path.hasPrefix("./") || path.hasPrefix("../") else { return path }
    var parts = base.split(separator: "/").map(String.init)
    if !parts.isEmpty { parts.removeLast() }
    for component in path.split(separator: "/").map(String.init) {
      if component == "." || component.isEmpty { continue }
      if component == ".." {
        if !parts.isEmpty { parts.removeLast() }
      } else {
        parts.append(component)
      }
    }
    return parts.joined(separator: "/")
  }
}
