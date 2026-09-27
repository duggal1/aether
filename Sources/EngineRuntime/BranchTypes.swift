import EngineCore
import Foundation
import Persistence
import Storage

// Durable identity for a forked browser state lineage. Branches must survive process
// restarts, so identity is UUID-backed rather than an EngineIdentifier counter (those
// are process-scoped and reused after restart).
public struct BranchID: Hashable, Sendable, Codable, CustomStringConvertible {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }

  public init?(string: String) {
    guard let value = UUID(uuidString: string) else { return nil }
    rawValue = value
  }

  public var description: String { rawValue.uuidString }

  private enum CodingKeys: String, CodingKey { case rawValue }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    rawValue = try container.decode(UUID.self, forKey: .rawValue)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(rawValue, forKey: .rawValue)
  }
}

public struct BranchCheckpointID: Hashable, Sendable, Codable, CustomStringConvertible {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }

  public init?(string: String) {
    guard let value = UUID(uuidString: string) else { return nil }
    rawValue = value
  }

  public var description: String { rawValue.uuidString }

  private enum CodingKeys: String, CodingKey { case rawValue }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    rawValue = try container.decode(UUID.self, forKey: .rawValue)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(rawValue, forKey: .rawValue)
  }
}

/// What a captured checkpoint actually contains. Counts, never values: summaries are
/// safe to expose to agents, logs, and event envelopes.
public struct BranchCheckpointSummary: Hashable, Sendable, Codable {
  public var id: BranchCheckpointID
  public var capturedAt: Double
  public var cookies: Int
  public var origins: Int
  public var localStorageEntries: Int
  public var historyEntries: Int
  public var sessionPages: Int
  public var permissions: Int
  public var bookmarks: Int
  public var downloads: Int
  /// True when cookies were read from the live `WKWebsiteDataStore` (the authoritative
  /// store for WebKit browsing), not only from the legacy jar or previous checkpoint rows.
  public var liveWebKitCookies: Bool
  /// Origins whose localStorage was read from live pages during capture.
  public var liveLocalStorageOrigins: [String]

  public init(
    id: BranchCheckpointID, capturedAt: Double, cookies: Int, origins: Int,
    localStorageEntries: Int, historyEntries: Int, sessionPages: Int, permissions: Int,
    bookmarks: Int, downloads: Int, liveWebKitCookies: Bool, liveLocalStorageOrigins: [String]
  ) {
    self.id = id
    self.capturedAt = capturedAt
    self.cookies = cookies
    self.origins = origins
    self.localStorageEntries = localStorageEntries
    self.historyEntries = historyEntries
    self.sessionPages = sessionPages
    self.permissions = permissions
    self.bookmarks = bookmarks
    self.downloads = downloads
    self.liveWebKitCookies = liveWebKitCookies
    self.liveLocalStorageOrigins = liveLocalStorageOrigins
  }
}

/// One source page in a checkpoint, identified by its slot in the durable session-page
/// ordering. `page` is the process-scoped `PageID` at capture time and only meaningful
/// inside the process that captured it; slot is the durable anchor used to rebuild the
/// source→branch page mapping after a restart.
public struct BranchSourcePage: Hashable, Sendable, Codable {
  public var page: UInt64
  public var slot: Int

  public init(page: UInt64, slot: Int) {
    self.page = page
    self.slot = slot
  }
}

/// What a checkpoint captured, plus the process-local source page identity needed for
/// fork re-targeting. Stored as JSON in the parent profile's `kv` table (scope
/// `branches`), so one checkpoint is written once no matter how many branches use it.
struct BranchCheckpointPayload: Codable, Sendable {
  var id: BranchCheckpointID
  var contextName: String
  var capturedAt: Double
  var cookies: [CookieRow]
  var localStorage: [LocalStorageRow]
  var history: [HistoryRow]
  var sessionPages: [SessionPageRow]
  var permissions: [PermissionRow]
  var bookmarks: [BookmarkRow]
  var downloads: [PersistedDownload]
  var searchProvider: BranchStoredSearchProvider?
  var sourcePages: [BranchSourcePage]
  var liveWebKitCookies: Bool
  var liveLocalStorageOrigins: [String]
  var sourceEphemeral: Bool

  var summary: BranchCheckpointSummary {
    let origins = Set(localStorage.map(\.origin)).count
    return BranchCheckpointSummary(
      id: id, capturedAt: capturedAt, cookies: cookies.count, origins: origins,
      localStorageEntries: localStorage.count, historyEntries: history.count,
      sessionPages: sessionPages.count,
      permissions: permissions.count, bookmarks: bookmarks.count, downloads: downloads.count,
      liveWebKitCookies: liveWebKitCookies, liveLocalStorageOrigins: liveLocalStorageOrigins)
  }
}

/// Search provider as persisted by `BrowserRuntime` (kv scope `search`). Kept as its own
/// type here so the payload does not couple to the actor's nested type.
struct BranchStoredSearchProvider: Codable, Sendable, Hashable {
  var endpoint: String
  var queryParameter: String
}

/// Durable record of one branch, stored in the parent profile's `kv` index.
struct BranchRecord: Codable, Hashable, Sendable {
  var id: BranchID
  var name: String
  var parentBranchID: BranchID?
  var checkpointID: BranchCheckpointID
  var checkpoint: BranchCheckpointSummary
  var createdAt: Double
  /// Absolute path of the branch's own profile directory (name == branch UUID, which
  /// is also its `WKWebsiteDataStore` identifier).
  var directory: String
  /// Absolute path of the parent profile directory that anchors this record.
  var parentDirectory: String
  var websiteDataStoreID: UUID
  var sourcePages: [BranchSourcePage]
  var liveWebKitCookieSeeding: Bool
}

/// Reverse pointer written into the branch's own profile so the ancestry is
/// discoverable from either direction.
struct BranchOriginRecord: Codable, Sendable {
  var branch: BranchID
  var parentBranch: BranchID?
  var checkpoint: BranchCheckpointID
  var parentDirectory: String
  var createdAt: Double
}

/// Report for a branch. Fidelity is reported honestly: callers must not treat a fork as
/// a byte-for-byte clone of arbitrary browser state.
public struct BrowserBranchInfo: Hashable, Sendable, Codable {
  public var id: BranchID
  public var name: String
  /// The live context currently attached to this branch, when one exists.
  public var contextID: ContextID?
  public var parentBranchID: BranchID?
  public var checkpointID: BranchCheckpointID
  public var checkpoint: BranchCheckpointSummary
  public var createdAt: Double
  public var pageCount: Int
  public var directory: String
  public var websiteDataStoreID: UUID
  public var live: Bool
  /// Source `PageID` raw value → branch `PageID` raw value, for re-targeting a running
  /// execution after a fork. Recomputed on attach from the durable slot order.
  public var pageMap: [String: String]
  /// Branch `PageID` raw values whose page is hibernated (`.discarded`) and therefore must
  /// be activated — `restorePage`, `page.restore`, or an exec `restore` step — before it
  /// can be driven. Forked branch pages start here: profiles restore pages lazily so a
  /// fork never blocks on the network. Empty once every page is live.
  public var restoreRequiredPages: [String]
  public var clonedState: [String]
  public var bestEffortState: [String]
  public var notClonedState: [String]

  public init(
    id: BranchID, name: String, contextID: ContextID?, parentBranchID: BranchID?,
    checkpointID: BranchCheckpointID, checkpoint: BranchCheckpointSummary, createdAt: Double,
    pageCount: Int, directory: String, websiteDataStoreID: UUID, live: Bool,
    pageMap: [String: String], restoreRequiredPages: [String] = [], clonedState: [String],
    bestEffortState: [String], notClonedState: [String]
  ) {
    self.id = id
    self.name = name
    self.contextID = contextID
    self.parentBranchID = parentBranchID
    self.checkpointID = checkpointID
    self.checkpoint = checkpoint
    self.createdAt = createdAt
    self.pageCount = pageCount
    self.directory = directory
    self.websiteDataStoreID = websiteDataStoreID
    self.live = live
    self.pageMap = pageMap
    self.restoreRequiredPages = restoreRequiredPages
    self.clonedState = clonedState
    self.bestEffortState = bestEffortState
    self.notClonedState = notClonedState
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, contextID, parentBranchID, checkpointID, checkpoint, createdAt, pageCount,
      directory, websiteDataStoreID, live, pageMap, restoreRequiredPages, clonedState,
      bestEffortState, notClonedState
  }

  /// Decoded field by field so a report written before `restoreRequiredPages` existed still
  /// decodes (treating the pages as requiring no restore).
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(BranchID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    contextID = try container.decodeIfPresent(ContextID.self, forKey: .contextID)
    parentBranchID = try container.decodeIfPresent(BranchID.self, forKey: .parentBranchID)
    checkpointID = try container.decode(BranchCheckpointID.self, forKey: .checkpointID)
    checkpoint = try container.decode(BranchCheckpointSummary.self, forKey: .checkpoint)
    createdAt = try container.decode(Double.self, forKey: .createdAt)
    pageCount = try container.decode(Int.self, forKey: .pageCount)
    directory = try container.decode(String.self, forKey: .directory)
    websiteDataStoreID = try container.decode(UUID.self, forKey: .websiteDataStoreID)
    live = try container.decode(Bool.self, forKey: .live)
    pageMap = try container.decode([String: String].self, forKey: .pageMap)
    restoreRequiredPages =
      try container.decodeIfPresent([String].self, forKey: .restoreRequiredPages) ?? []
    clonedState = try container.decode([String].self, forKey: .clonedState)
    bestEffortState = try container.decode([String].self, forKey: .bestEffortState)
    notClonedState = try container.decode([String].self, forKey: .notClonedState)
  }
}

/// Static fidelity catalog. `notCloned` entries are physically unreachable through
/// WebKit's public API; listing them here is the honest contract, not a TODO.
public enum BranchStateCatalog {
  public static let cloned = [
    "cookies", "localStorage", "navigationHistory", "sessionPages", "permissions",
    "downloadsMetadata", "bookmarks", "searchProvider",
  ]
  public static let bestEffort = [
    "cookiesSeededIntoWebKitStore"
  ]
  public static let notCloned = [
    "indexedDB", "serviceWorkers", "cacheStorage", "webKitHTTPCache", "sessionStorage",
    "webExtensions", "clientCertificates", "serverBoundSessions",
    // The checkpoint captures localStorage and the branch profile stores those rows,
    // but WebKit exposes no public API to seed a website data store's localStorage
    // without a live page at the origin, so a forked page starts with an empty
    // localStorage until a future navigation-time rehydration is implemented.
    "localStorageAutoRehydration",
  ]
}

public enum BranchError: Error, Sendable, CustomStringConvertible {
  case notFound(BranchID)
  case checkpointNotFound(BranchCheckpointID)
  case hasChildren(BranchID)
  case directoryMissing(String)
  case parentUnavailable(String)
  case invalidIdentifier(String)
  case ephemeralContext

  public var description: String {
    switch self {
    case .notFound(let id): return "Branch not found: \(id)"
    case .checkpointNotFound(let id): return "Branch checkpoint not found: \(id)"
    case .hasChildren(let id): return "Branch has child branches; delete them first: \(id)"
    case .directoryMissing(let path): return "Branch directory is missing: \(path)"
    case .parentUnavailable(let path): return "Branch parent profile is unavailable: \(path)"
    case .invalidIdentifier(let value): return "Invalid branch identifier: \(value)"
    case .ephemeralContext: return "Ephemeral browser state cannot be copied into a durable branch"
    }
  }
}

/// Layout and key conventions. Branch working state lives under the parent profile so
/// one directory tree carries ancestry; the branch directory's name is the branch UUID,
/// which is also its WebKit website-data-store identifier (same convention as
/// `openProfile`, which reads the UUID from the directory name).
enum BranchLayout {
  static let folderName = "Branches"

  static func directory(parent: URL, branch: BranchID) -> URL {
    parent.appendingPathComponent(folderName, isDirectory: true)
      .appendingPathComponent(branch.rawValue.uuidString, isDirectory: true)
  }
}

enum BranchKV {
  static let scope = "branches"
  static let indexKey = "index"
  static let branchScope = "branch"
  static let originKey = "origin"

  static func checkpointKey(_ id: BranchCheckpointID) -> String {
    "checkpoint:\(id.rawValue.uuidString)"
  }
}
