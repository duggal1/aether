import Foundation
import Persistence
import Testing

private func freshDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

@Test func cookiesRoundTrip() throws {
  let store = try ProfileStore.open(directory: freshDirectory())
  defer { store.close() }
  let expires = Date(timeIntervalSince1970: 2_000_000_000)
  try store.saveCookies([
    CookieRow(
      name: "session", value: "abc", domain: "example.com", path: "/", expires: expires,
      secure: true, httpOnly: true, sameSite: "lax"),
    CookieRow(name: "theme", value: "dark", domain: "example.com", path: "/app"),
  ])
  let loaded = try store.loadCookies()
  #expect(loaded.count == 2)
  let session = try #require(loaded.first { $0.name == "session" })
  #expect(session.value == "abc")
  #expect(session.expires == expires)
  #expect(session.secure && session.httpOnly)
  #expect(session.sameSite == "lax")
  try store.saveCookies([])
  #expect(try store.loadCookies().isEmpty)
}

@Test func localStorageRoundTrip() throws {
  let store = try ProfileStore.open(directory: freshDirectory())
  defer { store.close() }
  try store.saveLocalStorage([
    LocalStorageRow(origin: "https://a.example", key: "token", value: "a"),
    LocalStorageRow(origin: "https://b.example", key: "token", value: "b"),
  ])
  let loaded = try store.loadLocalStorage()
  #expect(loaded.count == 2)
  #expect(loaded.contains(LocalStorageRow(origin: "https://a.example", key: "token", value: "a")))
}

@Test func historyAndSessionRoundTrip() throws {
  let store = try ProfileStore.open(directory: freshDirectory())
  defer { store.close() }
  try store.saveHistory([
    HistoryRow(context: "work", slot: 0, index: 0, url: "https://example.com/"),
    HistoryRow(context: "work", slot: 0, index: 1, url: "https://example.com/next"),
  ])
  try store.saveSessionPages([
    SessionPageRow(
      context: "work", slot: 0, historyIndex: 1, viewportWidth: 1280, viewportHeight: 800)
  ])
  let history = try store.loadHistory()
  #expect(history.map(\.url) == ["https://example.com/", "https://example.com/next"])
  let pages = try store.loadSessionPages()
  #expect(pages.count == 1)
  #expect(pages[0].historyIndex == 1)
  #expect(pages[0].viewportWidth == 1280)
}

@Test func permissionsRoundTrip() throws {
  let store = try ProfileStore.open(directory: freshDirectory())
  defer { store.close() }
  try store.savePermissions([
    PermissionRow(origin: "https://example.com", permission: "camera", decision: "deny"),
    PermissionRow(origin: "https://example.com", permission: "geolocation", decision: "allow"),
  ])
  let loaded = try store.loadPermissions()
  #expect(loaded.count == 2)
  #expect(
    loaded.contains(
      PermissionRow(origin: "https://example.com", permission: "camera", decision: "deny")))
}

@Test func cacheEntryAndBlobRoundTripAcrossReopen() throws {
  let directory = try freshDirectory()
  let body = Data("hello-cache".utf8)
  let hash = DiskCache.sha256Hex(body)
  let entry = CacheEntry(
    url: "https://example.com/app.css", status: 200, headersJSON: "{\"etag\":\"\\\"v1\\\"\"}",
    etag: "\"v1\"", storedAt: Date(timeIntervalSince1970: 1_700_000_000), maxAge: 60,
    bodyHash: hash, bodySize: body.count)
  let first = try ProfileStore.open(directory: directory)
  try first.blobs.write(hash: hash, data: body)
  try first.saveCacheEntries([entry])
  first.close()
  let second = try ProfileStore.open(directory: directory)
  defer { second.close() }
  let loaded = try second.loadCacheEntries()
  #expect(loaded == [entry])
  #expect(second.blobs.read(hash: hash) == body)
}

@Test func checkpointsRoundTrip() throws {
  let store = try ProfileStore.open(directory: freshDirectory())
  defer { store.close() }
  try store.setKV(scope: "checkpoints", key: "agent-1", value: Data("{\"step\":3}".utf8))
  #expect(try store.getKV(scope: "checkpoints", key: "agent-1") == Data("{\"step\":3}".utf8))
  #expect(try store.listKeys(scope: "checkpoints") == ["agent-1"])
  try store.setKV(scope: "checkpoints", key: "agent-1", value: Data("{\"step\":4}".utf8))
  #expect(try store.getKV(scope: "checkpoints", key: "agent-1") == Data("{\"step\":4}".utf8))
  try store.deleteKV(scope: "checkpoints", key: "agent-1")
  #expect(try store.getKV(scope: "checkpoints", key: "agent-1") == nil)
}

@Test func journalIsWal() throws {
  let store = try ProfileStore.open(directory: freshDirectory())
  defer { store.close() }
  #expect(store.journalMode().lowercased() == "wal")
}

@Test func diskCacheEnforcesByteBound() throws {
  let cache = DiskCache(
    root: try freshDirectory(), maxBytes: 20)
  let first = Data(repeating: 1, count: 10)
  let second = Data(repeating: 2, count: 10)
  let third = Data(repeating: 3, count: 10)
  try cache.write(hash: DiskCache.sha256Hex(first), data: first)
  try cache.write(hash: DiskCache.sha256Hex(second), data: second)
  try cache.write(hash: DiskCache.sha256Hex(third), data: third)
  #expect(cache.totalBytes() == 30)
  let remaining = try cache.evict(maxBytes: 20, keeping: [])
  #expect(remaining <= 20)
  #expect(cache.read(hash: DiskCache.sha256Hex(third)) == third)
}

@Test func invalidBlobHashIsRejected() throws {
  let cache = DiskCache(root: freshDirectory())
  #expect(!DiskCache.isValidHash("../escape"))
  #expect(!DiskCache.isValidHash(""))
}

@Test func bulkCookieInsertStaysBounded() throws {
  let store = try ProfileStore.open(directory: freshDirectory())
  defer { store.close() }
  try store.saveCookies(
    (0..<2000).map { index in
      CookieRow(
        name: "k\(index)", value: "v\(index)", domain: "example.com", path: "/")
    })
  #expect(try store.loadCookies().count == 2000)
}
