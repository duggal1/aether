import Foundation

public struct CacheSnapshot: Sendable {
  public var response: HTTPResponse
  public var storedAt: Date

  public init(response: HTTPResponse, storedAt: Date) {
    self.response = response
    self.storedAt = storedAt
  }
}

public actor HTTPCache {
  private struct Entry: Sendable {
    var response: HTTPResponse
    var storedAt: Date
    var lastAccess: UInt64
    var byteCount: Int
  }

  private var entries: [URL: Entry] = [:]
  private var accessCounter: UInt64 = 0
  private var bytes = 0
  public let maximumBytes: Int

  public init(maximumBytes: Int = 64 * 1024 * 1024) {
    self.maximumBytes = max(0, maximumBytes)
  }

  public func response(for url: URL) -> HTTPResponse? {
    guard var entry = entries[url], isFresh(entry) else {
      if entries[url] != nil { remove(url) }
      return nil
    }
    accessCounter &+= 1
    entry.lastAccess = accessCounter
    entries[url] = entry
    var response = entry.response
    response.fromCache = true
    response.durationMilliseconds = 0
    return response
  }

  public func store(_ response: HTTPResponse) {
    guard response.statusCode == 200,
      response.body.count <= maximumBytes,
      cacheable(response)
    else { return }
    if let old = entries[response.url] { bytes -= old.byteCount }
    accessCounter &+= 1
    let entry = Entry(
      response: response, storedAt: Date(), lastAccess: accessCounter,
      byteCount: response.body.count)
    entries[response.url] = entry
    bytes += entry.byteCount
    evictIfNeeded()
  }

  public func removeAll() {
    entries.removeAll(keepingCapacity: false)
    bytes = 0
  }

  public func snapshot() -> [CacheSnapshot] {
    entries.values.filter { isFresh($0) }.map {
      CacheSnapshot(response: $0.response, storedAt: $0.storedAt)
    }
  }

  public func restore(_ snapshot: CacheSnapshot) {
    guard snapshot.response.statusCode == 200,
      snapshot.response.body.count <= maximumBytes,
      cacheable(snapshot.response)
    else { return }
    if let old = entries[snapshot.response.url] { bytes -= old.byteCount }
    accessCounter &+= 1
    let entry = Entry(
      response: snapshot.response, storedAt: snapshot.storedAt, lastAccess: accessCounter,
      byteCount: snapshot.response.body.count)
    entries[snapshot.response.url] = entry
    bytes += entry.byteCount
    evictIfNeeded()
  }

  public var totalBytes: Int { bytes }
  public var count: Int { entries.count }

  private func cacheable(_ response: HTTPResponse) -> Bool {
    let control = header("cache-control", in: response.headers).lowercased()
    return !control.contains("no-store") && !control.contains("private")
  }

  private func isFresh(_ entry: Entry) -> Bool {
    let control = header("cache-control", in: entry.response.headers).lowercased()
    if let range = control.range(of: "max-age=") {
      let suffix = control[range.upperBound...]
      let number = suffix.prefix { $0.isNumber }
      if let seconds = TimeInterval(number) {
        return Date().timeIntervalSince(entry.storedAt) <= seconds
      }
    }
    return Date().timeIntervalSince(entry.storedAt) <= 60
  }

  private func evictIfNeeded() {
    while bytes > maximumBytes,
      let victim = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key
    {
      remove(victim)
    }
  }

  private func remove(_ url: URL) {
    if let entry = entries.removeValue(forKey: url) { bytes -= entry.byteCount }
  }

  private func header(_ name: String, in headers: [String: String]) -> String {
    headers.first(where: { $0.key.lowercased() == name.lowercased() })?.value ?? ""
  }
}
