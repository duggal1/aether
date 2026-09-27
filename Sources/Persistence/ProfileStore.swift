import Foundation

public struct CookieRow: Hashable, Sendable, Codable {
  public var name: String
  public var value: String
  public var domain: String
  public var path: String
  public var expires: Date?
  public var secure: Bool
  public var httpOnly: Bool
  public var sameSite: String?
  public var hostOnly: Bool

  public init(
    name: String, value: String, domain: String, path: String = "/",
    expires: Date? = nil, secure: Bool = false, httpOnly: Bool = false,
    sameSite: String? = nil, hostOnly: Bool = true
  ) {
    self.name = name
    self.value = value
    self.domain = domain
    self.path = path
    self.expires = expires
    self.secure = secure
    self.httpOnly = httpOnly
    self.sameSite = sameSite
    self.hostOnly = hostOnly
  }
}

public struct LocalStorageRow: Hashable, Sendable, Codable {
  public var origin: String
  public var key: String
  public var value: String

  public init(origin: String, key: String, value: String) {
    self.origin = origin
    self.key = key
    self.value = value
  }
}

public struct HistoryRow: Hashable, Sendable, Codable {
  public var context: String
  public var slot: Int
  public var index: Int
  public var url: String

  public init(context: String, slot: Int, index: Int, url: String) {
    self.context = context
    self.slot = slot
    self.index = index
    self.url = url
  }
}

public struct SessionPageRow: Hashable, Sendable, Codable {
  public var context: String
  public var slot: Int
  public var historyIndex: Int
  public var viewportWidth: Double
  public var viewportHeight: Double

  public init(
    context: String, slot: Int, historyIndex: Int, viewportWidth: Double,
    viewportHeight: Double
  ) {
    self.context = context
    self.slot = slot
    self.historyIndex = historyIndex
    self.viewportWidth = viewportWidth
    self.viewportHeight = viewportHeight
  }
}

public struct PermissionRow: Hashable, Sendable, Codable {
  public var origin: String
  public var permission: String
  public var decision: String

  public init(origin: String, permission: String, decision: String) {
    self.origin = origin
    self.permission = permission
    self.decision = decision
  }
}

public struct BookmarkRow: Hashable, Sendable, Codable {
  public var url: String
  public var title: String
  public var createdAt: Date

  public init(url: String, title: String, createdAt: Date) {
    self.url = url
    self.title = title
    self.createdAt = createdAt
  }
}

public struct CacheEntry: Hashable, Sendable, Codable {
  public var url: String
  public var status: Int
  public var headersJSON: String
  public var etag: String?
  public var storedAt: Date
  public var maxAge: Double
  public var bodyHash: String
  public var bodySize: Int

  public init(
    url: String, status: Int, headersJSON: String, etag: String? = nil,
    storedAt: Date, maxAge: Double, bodyHash: String, bodySize: Int
  ) {
    self.url = url
    self.status = status
    self.headersJSON = headersJSON
    self.etag = etag
    self.storedAt = storedAt
    self.maxAge = maxAge
    self.bodyHash = bodyHash
    self.bodySize = bodySize
  }
}

public enum ProfileError: Error, Sendable, CustomStringConvertible {
  case versionMismatch(Int)
  case io(String)

  public var description: String {
    switch self {
    case .versionMismatch(let value): return "Unsupported profile database version: \(value)"
    case .io(let value): return "Profile I/O failed: \(value)"
    }
  }
}

public final class ProfileStore: Sendable {
  public static let schemaVersion = 4

  public let directory: URL
  public let blobs: DiskCache
  private let database: SQLiteStore

  private init(directory: URL, database: SQLiteStore, blobs: DiskCache) {
    self.directory = directory
    self.database = database
    self.blobs = blobs
  }

  public static func open(directory: URL, diskCacheBytes: Int = 256 * 1024 * 1024) throws
    -> ProfileStore
  {
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true)
    } catch {
      throw ProfileError.io(error.localizedDescription)
    }
    let blobs = DiskCache(
      root: directory.appendingPathComponent("Cache/objects"), maxBytes: diskCacheBytes)
    let database = try SQLiteStore(
      path: directory.appendingPathComponent("state.sqlite").path)
    let store = ProfileStore(directory: directory, database: database, blobs: blobs)
    try store.migrate()
    return store
  }

  public func close() {
    database.close()
  }

  public func fileBytes() -> Int {
    let files = ["state.sqlite", "state.sqlite-wal", "state.sqlite-shm"]
    return files.reduce(0) { total, name in
      let url = directory.appendingPathComponent(name)
      guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
        let size = values.fileSize
      else { return total }
      return total + size
    }
  }

  public func journalMode() -> String {
    (try? database.query("PRAGMA journal_mode;").first?.first?.textValue) ?? ""
  }

  public func saveCookies(_ rows: [CookieRow]) throws {
    try database.withTransaction { connection in try saveCookies(rows, on: connection) }
  }

  private func saveCookies(_ rows: [CookieRow], on connection: SQLiteConnection) throws {
    try connection.exec("DELETE FROM cookies;")
    for row in rows {
      try connection.execute(
        "INSERT INTO cookies(name,value,domain,path,expires,secure,http_only,same_site,host_only) VALUES(?,?,?,?,?,?,?,?,?);",
        [
          .text(row.name), .text(row.value), .text(row.domain), .text(row.path),
          row.expires.map { .real($0.timeIntervalSince1970) } ?? .null,
          .integer(row.secure ? 1 : 0), .integer(row.httpOnly ? 1 : 0),
          row.sameSite.map { .text($0) } ?? .null,
          .integer(row.hostOnly ? 1 : 0),
        ])
    }
  }

  public func loadCookies() throws -> [CookieRow] {
    try database.query(
      "SELECT name,value,domain,path,expires,secure,http_only,same_site,host_only FROM cookies;"
    ).map { row in
      CookieRow(
        name: row[0].textValue, value: row[1].textValue, domain: row[2].textValue,
        path: row[3].textValue.isEmpty ? "/" : row[3].textValue,
        expires: row[4].dateValue, secure: row[5].boolValue, httpOnly: row[6].boolValue,
        sameSite: row[7].textOrNil, hostOnly: row.count > 8 ? row[8].boolValue : true)
    }
  }

  public func saveLocalStorage(_ rows: [LocalStorageRow]) throws {
    try database.withTransaction { connection in try saveLocalStorage(rows, on: connection) }
  }

  private func saveLocalStorage(_ rows: [LocalStorageRow], on connection: SQLiteConnection) throws {
    try connection.exec("DELETE FROM local_storage;")
    for row in rows {
      try connection.execute(
        "INSERT INTO local_storage(origin,key,value) VALUES(?,?,?);",
        [.text(row.origin), .text(row.key), .text(row.value)])
    }
  }

  public func loadLocalStorage() throws -> [LocalStorageRow] {
    try database.query("SELECT origin,key,value FROM local_storage;").map { row in
      LocalStorageRow(origin: row[0].textValue, key: row[1].textValue, value: row[2].textValue)
    }
  }

  public func saveHistory(_ rows: [HistoryRow]) throws {
    try database.withTransaction { connection in try saveHistory(rows, on: connection) }
  }

  private func saveHistory(_ rows: [HistoryRow], on connection: SQLiteConnection) throws {
    try connection.exec("DELETE FROM history;")
    for row in rows {
      try connection.execute(
        "INSERT INTO history(context_name,slot,idx,url) VALUES(?,?,?,?);",
        [
          .text(row.context), .integer(Int64(row.slot)), .integer(Int64(row.index)),
          .text(row.url),
        ])
    }
  }

  public func loadHistory() throws -> [HistoryRow] {
    try database.query(
      "SELECT context_name,slot,idx,url FROM history ORDER BY context_name,slot,idx;"
    ).map { row in
      HistoryRow(
        context: row[0].textValue, slot: row[1].intValue, index: row[2].intValue,
        url: row[3].textValue)
    }
  }

  public func saveSessionPages(_ rows: [SessionPageRow]) throws {
    try database.withTransaction { connection in try saveSessionPages(rows, on: connection) }
  }

  private func saveSessionPages(_ rows: [SessionPageRow], on connection: SQLiteConnection) throws {
    try connection.exec("DELETE FROM session_pages;")
    for row in rows {
      try connection.execute(
        "INSERT INTO session_pages(context_name,slot,history_index,viewport_w,viewport_h) VALUES(?,?,?,?,?);",
        [
          .text(row.context), .integer(Int64(row.slot)),
          .integer(Int64(row.historyIndex)), .real(row.viewportWidth),
          .real(row.viewportHeight),
        ])
    }
  }

  public func loadSessionPages() throws -> [SessionPageRow] {
    try database.query(
      "SELECT context_name,slot,history_index,viewport_w,viewport_h FROM session_pages ORDER BY context_name,slot;"
    ).map { row in
      SessionPageRow(
        context: row[0].textValue, slot: row[1].intValue, historyIndex: row[2].intValue,
        viewportWidth: row[3].doubleValue, viewportHeight: row[4].doubleValue)
    }
  }

  public func savePermissions(_ rows: [PermissionRow]) throws {
    try database.withTransaction { connection in try savePermissions(rows, on: connection) }
  }

  private func savePermissions(_ rows: [PermissionRow], on connection: SQLiteConnection) throws {
    try connection.exec("DELETE FROM permissions;")
    for row in rows {
      try connection.execute(
        "INSERT INTO permissions(origin,permission,decision) VALUES(?,?,?);",
        [.text(row.origin), .text(row.permission), .text(row.decision)])
    }
  }

  public func loadPermissions() throws -> [PermissionRow] {
    try database.query("SELECT origin,permission,decision FROM permissions;").map { row in
      PermissionRow(
        origin: row[0].textValue, permission: row[1].textValue, decision: row[2].textValue)
    }
  }

  public func saveBookmarks(_ rows: [BookmarkRow]) throws {
    try database.withTransaction { connection in try saveBookmarks(rows, on: connection) }
  }

  private func saveBookmarks(_ rows: [BookmarkRow], on connection: SQLiteConnection) throws {
    try connection.exec("DELETE FROM bookmarks;")
    for row in rows {
      try connection.execute(
        "INSERT INTO bookmarks(url,title,created_at) VALUES(?,?,?);",
        [
          .text(row.url), .text(row.title),
          .real(row.createdAt.timeIntervalSince1970),
        ])
    }
  }

  public func loadBookmarks() throws -> [BookmarkRow] {
    try database.query("SELECT url,title,created_at FROM bookmarks ORDER BY created_at;").compactMap
      { row in
        guard let createdAt = row[2].dateValueOrNil else { return nil }
        return BookmarkRow(url: row[0].textValue, title: row[1].textValue, createdAt: createdAt)
      }
  }

  // MARK: - Credential metadata (lookup only; secrets live in the Keychain)

  /// Upserts one credential record. No secret material is written here.
  public func saveCredential(_ record: CredentialRecord) throws {
    try database.execute(
      "INSERT INTO credentials(id,profile_id,origin,username,label,created_at,updated_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET origin=excluded.origin, username=excluded.username, label=excluded.label, updated_at=excluded.updated_at;",
      [
        .text(record.id), .text(record.profileID), .text(record.origin),
        .text(record.username), .text(record.label),
        .real(record.createdAt.timeIntervalSince1970),
        .real(record.updatedAt.timeIntervalSince1970),
      ])
  }

  public func loadCredentials(origin: String? = nil) throws -> [CredentialRecord] {
    let rows: [[SQLiteValue]]
    if let origin {
      rows = try database.query(
        "SELECT id,profile_id,origin,username,label,created_at,updated_at FROM credentials WHERE origin=? ORDER BY username;",
        [.text(origin)])
    } else {
      rows = try database.query(
        "SELECT id,profile_id,origin,username,label,created_at,updated_at FROM credentials ORDER BY origin,username;")
    }
    return rows.compactMap { row in
      guard row.count == 7,
        let createdAt = row[5].dateValueOrNil, let updatedAt = row[6].dateValueOrNil
      else { return nil }
      return CredentialRecord(
        id: row[0].textValue, profileID: row[1].textValue, origin: row[2].textValue,
        username: row[3].textValue, label: row[4].textValue,
        createdAt: createdAt, updatedAt: updatedAt)
    }
  }

  public func loadCredential(id: String) throws -> CredentialRecord? {
    try database.query(
      "SELECT id,profile_id,origin,username,label,created_at,updated_at FROM credentials WHERE id=?;",
      [.text(id)]
    ).compactMap { row -> CredentialRecord? in
      guard row.count == 7,
        let createdAt = row[5].dateValueOrNil, let updatedAt = row[6].dateValueOrNil
      else { return nil }
      return CredentialRecord(
        id: row[0].textValue, profileID: row[1].textValue, origin: row[2].textValue,
        username: row[3].textValue, label: row[4].textValue,
        createdAt: createdAt, updatedAt: updatedAt)
    }.first
  }

  @discardableResult
  public func deleteCredential(id: String) throws -> Bool {
    try database.execute("DELETE FROM credentials WHERE id=?;", [.text(id)]) > 0
  }

  public func saveCacheEntries(_ entries: [CacheEntry]) throws {
    try database.withTransaction { connection in try saveCacheEntries(entries, on: connection) }
  }

  private func saveCacheEntries(_ entries: [CacheEntry], on connection: SQLiteConnection) throws {
    try connection.exec("DELETE FROM cache_entries;")
    for entry in entries {
      try connection.execute(
        "INSERT INTO cache_entries(url,status,headers,etag,stored_at,max_age,body_hash,body_size) VALUES(?,?,?,?,?,?,?,?);",
        [
          .text(entry.url), .integer(Int64(entry.status)), .text(entry.headersJSON),
          entry.etag.map { .text($0) } ?? .null, .real(entry.storedAt.timeIntervalSince1970),
          .real(entry.maxAge), .text(entry.bodyHash), .integer(Int64(entry.bodySize)),
        ])
    }
  }

  /// Writes every checkpoint table in a single SQLite transaction so one
  /// checkpoint costs one commit instead of one per table. A nil
  /// cacheEntries skips the cache-table rewrite when there is nothing to
  /// snapshot; stale rows self-heal at attach time through blob pruning.
  public func saveCheckpointTables(
    cookies: [CookieRow], localStorage: [LocalStorageRow], history: [HistoryRow],
    sessionPages: [SessionPageRow], permissions: [PermissionRow], bookmarks: [BookmarkRow],
    cacheEntries: [CacheEntry]?
  ) throws {
    try database.withTransaction { connection in
      try saveCookies(cookies, on: connection)
      if let cacheEntries { try saveCacheEntries(cacheEntries, on: connection) }
      try saveLocalStorage(localStorage, on: connection)
      try saveHistory(history, on: connection)
      try saveSessionPages(sessionPages, on: connection)
      try savePermissions(permissions, on: connection)
      try saveBookmarks(bookmarks, on: connection)
    }
  }

  public func loadCacheEntries() throws -> [CacheEntry] {
    try database.query(
      "SELECT url,status,headers,etag,stored_at,max_age,body_hash,body_size FROM cache_entries ORDER BY stored_at;"
    ).compactMap { row in
      guard let storedAt = row[4].dateValueOrNil else { return nil }
      return CacheEntry(
        url: row[0].textValue, status: row[1].intValue, headersJSON: row[2].textValue,
        etag: row[3].textOrNil, storedAt: storedAt, maxAge: row[5].doubleValue,
        bodyHash: row[6].textValue, bodySize: row[7].intValue)
    }
  }

  public func deleteCacheEntry(url: String) throws {
    try database.execute("DELETE FROM cache_entries WHERE url=?;", [.text(url)])
  }

  /// Drops Aether's duplicate HTTP response cache. WKWebView serves all
  /// production navigations from its own website data store with standard
  /// revalidation, so these rows and blobs only cost I/O and can never
  /// serve a page. Safe to purge: every entry is a reconstructible
  /// network response, never user data.
  public func dropResponseCache() throws {
    try database.execute("DELETE FROM cache_entries;")
    _ = try blobs.evict(maxBytes: 0, keeping: [])
  }

  public func setKV(scope: String, key: String, value: Data) throws {
    try database.execute(
      "INSERT INTO kv(scope,key,value,updated_at) VALUES(?,?,?,?) ON CONFLICT(scope,key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at;",
      [.text(scope), .text(key), .blob(value), .real(Date().timeIntervalSince1970)])
  }

  public func getKV(scope: String, key: String) throws -> Data? {
    try database.query("SELECT value FROM kv WHERE scope=? AND key=?;", [.text(scope), .text(key)])
      .first?.first?.blobValue
  }

  public func deleteKV(scope: String, key: String) throws {
    try database.execute("DELETE FROM kv WHERE scope=? AND key=?;", [.text(scope), .text(key)])
  }

  public func listKeys(scope: String) throws -> [String] {
    try database.query("SELECT key FROM kv WHERE scope=? ORDER BY key;", [.text(scope)])
      .map { $0[0].textValue }
  }

  @discardableResult
  public func evictBlobs(keeping: Set<String>, maxBytes: Int) throws -> Int {
    try blobs.evict(maxBytes: maxBytes, keeping: keeping)
  }

  private func migrate() throws {
    let version = try database.query("PRAGMA user_version;").first?.first?.intValue ?? 0
    guard version <= Self.schemaVersion else {
      throw ProfileError.versionMismatch(version)
    }
    if version < 1 {
      try database.exec(
        "CREATE TABLE IF NOT EXISTS cookies(name TEXT NOT NULL, value TEXT NOT NULL, domain TEXT NOT NULL, path TEXT NOT NULL DEFAULT '/', expires REAL, secure INTEGER NOT NULL DEFAULT 0, http_only INTEGER NOT NULL DEFAULT 0, same_site TEXT, host_only INTEGER NOT NULL DEFAULT 1, PRIMARY KEY(domain, path, name));"
      )
      try database.exec(
        "CREATE TABLE IF NOT EXISTS local_storage(origin TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(origin, key));"
      )
      try database.exec(
        "CREATE TABLE IF NOT EXISTS history(context_name TEXT NOT NULL, slot INTEGER NOT NULL, idx INTEGER NOT NULL, url TEXT NOT NULL, PRIMARY KEY(context_name, slot, idx));"
      )
      try database.exec(
        "CREATE TABLE IF NOT EXISTS session_pages(context_name TEXT NOT NULL, slot INTEGER NOT NULL, history_index INTEGER NOT NULL, viewport_w REAL NOT NULL, viewport_h REAL NOT NULL, PRIMARY KEY(context_name, slot));"
      )
      try database.exec(
        "CREATE TABLE IF NOT EXISTS permissions(origin TEXT NOT NULL, permission TEXT NOT NULL, decision TEXT NOT NULL, PRIMARY KEY(origin, permission));"
      )
      try database.exec(
        "CREATE TABLE IF NOT EXISTS cache_entries(url TEXT PRIMARY KEY, status INTEGER NOT NULL, headers TEXT NOT NULL, etag TEXT, stored_at REAL NOT NULL, max_age REAL NOT NULL, body_hash TEXT NOT NULL, body_size INTEGER NOT NULL);"
      )
      try database.exec(
        "CREATE TABLE IF NOT EXISTS kv(scope TEXT NOT NULL, key TEXT NOT NULL, value BLOB NOT NULL, updated_at REAL NOT NULL, PRIMARY KEY(scope, key));"
      )
      try database.exec("PRAGMA user_version=1;")
    }
    if version < 2 {
      if version >= 1 {
        try database.exec(
          "ALTER TABLE cookies ADD COLUMN host_only INTEGER NOT NULL DEFAULT 1;")
      }
      try database.exec("PRAGMA user_version=2;")
    }
    if version < 3 {
      try database.exec(
        "CREATE TABLE IF NOT EXISTS bookmarks(url TEXT PRIMARY KEY, title TEXT NOT NULL DEFAULT '', created_at REAL NOT NULL);"
      )
      try database.exec("PRAGMA user_version=3;")
    }
    if version < 4 {
      try database.exec(
        "CREATE TABLE IF NOT EXISTS credentials(id TEXT PRIMARY KEY, profile_id TEXT NOT NULL, origin TEXT NOT NULL, username TEXT NOT NULL, label TEXT NOT NULL DEFAULT '', created_at REAL NOT NULL, updated_at REAL NOT NULL);"
      )
      try database.exec(
        "CREATE INDEX IF NOT EXISTS idx_credentials_origin ON credentials(origin);")
      try database.exec("PRAGMA user_version=4;")
    }
  }
}

private extension SQLiteValue {
  var textValue: String {
    if case .text(let value) = self { return value }
    return ""
  }

  var textOrNil: String? {
    if case .text(let value) = self { return value }
    return nil
  }

  var intValue: Int {
    switch self {
    case .integer(let value): return Int(value)
    case .real(let value): return Int(value)
    case .text(let value): return Int(value) ?? 0
    default: return 0
    }
  }

  var doubleValue: Double {
    switch self {
    case .real(let value): return value
    case .integer(let value): return Double(value)
    case .text(let value): return Double(value) ?? 0
    default: return 0
    }
  }

  var boolValue: Bool { intValue != 0 }

  var dateValue: Date? {
    switch self {
    case .real(let value): return Date(timeIntervalSince1970: value)
    case .integer(let value): return Date(timeIntervalSince1970: Double(value))
    default: return nil
    }
  }

  var dateValueOrNil: Date? { dateValue }

  var blobValue: Data? {
    if case .blob(let value) = self { return value }
    return nil
  }
}
