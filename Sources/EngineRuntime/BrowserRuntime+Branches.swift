import BrowserEvents
import EngineCore
import Foundation
import Persistence
import Storage

extension BrowserRuntime {
  /// Captures the durable Aether profile state used by a later fork. WebKit does not
  /// expose sessionStorage, IndexedDB, service-worker state, or a portable history stack.
  public func checkpointBranch(contextID: ContextID) async throws -> BranchCheckpointSummary {
    guard let context = contexts[contextID], let profile = context.profile else {
      if contexts[contextID] == nil { throw BrowserRuntimeError.contextNotFound(contextID) }
      throw BrowserRuntimeError.profileNotConfigured(contextID)
    }
    guard !webEphemeral.contains(contextID) else { throw BranchError.ephemeralContext }
    try await checkpoint(contextID: contextID)

    let now = nowSeconds()
    let id = BranchCheckpointID()
    let pages = context.pages.values.sorted { $0.id.rawValue < $1.id.rawValue }
    let sessions = try profile.loadSessionPages().filter { $0.context == context.name }
      .sorted { $0.slot < $1.slot }
    let histories = try profile.loadHistory().filter { $0.context == context.name }
    let downloadsData = try profile.getKV(scope: "downloads", key: "all")
    let downloads = downloadsData.flatMap {
      try? JSONDecoder().decode([PersistedDownload].self, from: $0)
    } ?? []
    let searchProvider = try profile.getKV(scope: "search", key: "provider").flatMap {
      try? JSONDecoder().decode(BranchStoredSearchProvider.self, from: $0)
    }
    let sourcePages = pages.enumerated().map {
      BranchSourcePage(page: $0.element.id.rawValue, slot: $0.offset)
    }
    let storedCookies = try profile.loadCookies()
    let storedCookieIndex = Dictionary(
      uniqueKeysWithValues: storedCookies.map {
        ("\($0.domain)|\($0.path)|\($0.name)", $0)
      })
    let liveCookies = try await listCookies(contextID: contextID)
    let cookies = liveCookies.map { live in
      let saved = storedCookieIndex["\(live.domain)|\(live.path)|\(live.name)"]
      return CookieRow(
        name: live.name, value: live.value, domain: live.domain, path: live.path,
        expires: saved?.expires, secure: live.secure, httpOnly: live.httpOnly,
        sameSite: live.sameSite ?? saved?.sameSite, hostOnly: saved?.hostOnly ?? false)
    }
    var localStorage = try profile.loadLocalStorage()
    let savedOrigins = Set(localStorage.map(\.origin))
    var observedOrigins: [String] = []
    for page in pages {
      guard let url = webStates[page.id]?.url, let host = url.host else { continue }
      let origin = "\(url.scheme ?? "https")://\(host)\(url.port.map { ":\($0)" } ?? "")"
      guard !observedOrigins.contains(origin),
        let values = try? await storageValues(contextID: contextID, origin: host)
      else { continue }
      localStorage.removeAll { $0.origin == origin }
      localStorage.append(contentsOf: values.map {
        LocalStorageRow(origin: origin, key: $0.key, value: $0.value)
      })
      observedOrigins.append(origin)
    }
    for origin in savedOrigins where !observedOrigins.contains(origin) {
      guard let host = URL(string: origin)?.host,
        let values = try? await storageValues(contextID: contextID, origin: host)
      else { continue }
      localStorage.removeAll { $0.origin == origin }
      localStorage.append(contentsOf: values.map {
        LocalStorageRow(origin: origin, key: $0.key, value: $0.value)
      })
      observedOrigins.append(origin)
    }
    let payload = BranchCheckpointPayload(
      id: id, contextName: context.name, capturedAt: now,
      cookies: cookies, localStorage: localStorage,
      history: histories, sessionPages: sessions, permissions: try profile.loadPermissions(),
      bookmarks: try profile.loadBookmarks(), downloads: downloads,
      searchProvider: searchProvider, sourcePages: sourcePages,
      liveWebKitCookies: true, liveLocalStorageOrigins: observedOrigins,
      sourceEphemeral: false)
    try profile.setKV(
      scope: BranchKV.scope, key: BranchKV.checkpointKey(id),
      value: try JSONEncoder().encode(payload))
    return payload.summary
  }

  /// Creates a new profile directory and WebKit website-data store from a durable
  /// checkpoint. Mutable server-side sessions are copied only as cookies; a server may
  /// invalidate or bind those credentials independently.
  public func forkBranch(
    contextID: ContextID, checkpointID: BranchCheckpointID, name: String
  ) async throws -> BrowserBranchInfo {
    guard let parent = contexts[contextID], let parentProfile = parent.profile else {
      if contexts[contextID] == nil { throw BrowserRuntimeError.contextNotFound(contextID) }
      throw BrowserRuntimeError.profileNotConfigured(contextID)
    }
    let payloadData = try parentProfile.getKV(
      scope: BranchKV.scope, key: BranchKV.checkpointKey(checkpointID))
    guard let payloadData,
      let payload = try? JSONDecoder().decode(BranchCheckpointPayload.self, from: payloadData)
    else { throw BranchError.checkpointNotFound(checkpointID) }
    guard !payload.sourceEphemeral else { throw BranchError.ephemeralContext }

    let branchID = BranchID()
    let branchName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !branchName.isEmpty, branchName.count <= 128 else {
      throw BranchError.invalidIdentifier(name)
    }
    let directory = BranchLayout.directory(parent: parentProfile.directory, branch: branchID)
    guard !FileManager.default.fileExists(atPath: directory.path) else {
      throw BranchError.invalidIdentifier(branchID.description)
    }
    let branchProfile = try ProfileStore.open(directory: directory)
    var branchProfileOpen = true
    defer { if branchProfileOpen { branchProfile.close() } }

    let branchContext = createContext(name: branchName).id
    do {
      let history = payload.history.map {
        HistoryRow(context: branchName, slot: $0.slot, index: $0.index, url: $0.url)
      }
      let sessionPages = payload.sessionPages.map {
        SessionPageRow(
          context: branchName, slot: $0.slot, historyIndex: $0.historyIndex,
          viewportWidth: $0.viewportWidth, viewportHeight: $0.viewportHeight)
      }
      try branchProfile.saveCheckpointTables(
        cookies: payload.cookies, localStorage: payload.localStorage, history: history,
        sessionPages: sessionPages, permissions: payload.permissions,
        bookmarks: payload.bookmarks, cacheEntries: nil)
      try branchProfile.setKV(
        scope: "downloads", key: "all", value: try JSONEncoder().encode(payload.downloads))
      if let searchProvider = payload.searchProvider {
        try branchProfile.setKV(
          scope: "search", key: "provider", value: try JSONEncoder().encode(searchProvider))
      }
      let now = nowSeconds()
      let origin = BranchOriginRecord(
        branch: branchID, parentBranch: contextBranches[contextID], checkpoint: checkpointID,
        parentDirectory: parentProfile.directory.path, createdAt: now)
      try branchProfile.setKV(
        scope: BranchKV.branchScope, key: BranchKV.originKey,
        value: try JSONEncoder().encode(origin))

      branchProfile.close()
      branchProfileOpen = false
      try await openProfile(contextID: branchContext, directory: directory)
      let webContext = try await webContextForCookies(branchContext)
      for cookie in payload.cookies {
        try await WebKitCookieBridge.set(
          webContext,
          input: WebCookieInput(
            name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path,
            secure: cookie.secure, httpOnly: cookie.httpOnly, expires: cookie.expires))
      }
      let record = BranchRecord(
        id: branchID, name: branchName, parentBranchID: contextBranches[contextID],
        checkpointID: checkpointID, checkpoint: payload.summary, createdAt: now,
        directory: directory.path, parentDirectory: parentProfile.directory.path,
        websiteDataStoreID: branchID.rawValue, sourcePages: payload.sourcePages,
        liveWebKitCookieSeeding: payload.liveWebKitCookies)
      var records = try loadBranchRecords(from: parentProfile)
      records.append(record)
      try saveBranchRecords(records, to: parentProfile)
      branchContexts[branchID] = branchContext
      contextBranches[branchContext] = branchID

      // Pages restored from the branch profile are hibernated on purpose (a fork must not
      // block on the network), so the report states exactly which pages the caller has to
      // activate before driving them instead of leaving them to hit an opaque error.
      let info = branchInfo(for: record)
      await events.publish(
        .branchCreated(parent: record.parentBranchID?.description ?? "root"),
        identity: BrowserEventIdentity(context: branchContext, branch: branchID.description))
      return info
    } catch {
      try? await destroyContext(branchContext)
      await purgeWebKitStore(identifier: branchID.rawValue)
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  /// Every branch in the tree rooted at `contextID`'s profile — children *and* their
  /// descendants. A branch's own children are recorded in the index of the profile it was
  /// forked from, so the tree is discovered by descending into each branch's directory.
  /// Records come back parent-before-child.
  public func listBranches(contextID: ContextID) throws -> [BrowserBranchInfo] {
    guard let context = contexts[contextID], let profile = context.profile else {
      if contexts[contextID] == nil { throw BrowserRuntimeError.contextNotFound(contextID) }
      throw BrowserRuntimeError.profileNotConfigured(contextID)
    }
    return try loadBranchTree(from: profile, directory: profile.directory)
      .map { branchInfo(for: $0) }
  }

  /// Depth-first walk of the branch tree. Directories are visited once; a branch that is
  /// currently attached is read through its live context's profile instead of a second
  /// handle, and every profile this call opens is closed before it returns.
  private func loadBranchTree(from root: ProfileStore, directory rootDirectory: URL)
    throws -> [BranchRecord]
  {
    var collected: [BranchRecord] = []
    var visited: Set<BranchID> = []
    var opened: [String: ProfileStore] = [:]
    defer { for store in opened.values { store.close() } }
    var pending: [(records: [BranchRecord], directory: String)] = [
      (try loadBranchRecords(from: root), rootDirectory.standardizedFileURL.path)
    ]
    while let next = pending.popLast() {
      for record in next.records {
        guard visited.insert(record.id).inserted else { continue }
        collected.append(record)
        let childDirectory = URL(fileURLWithPath: record.directory).standardizedFileURL
        guard childDirectory.path != next.directory,
          FileManager.default.fileExists(atPath: childDirectory.path)
        else { continue }
        let children: [BranchRecord]
        if let attached = branchContexts[record.id], let profile = contexts[attached]?.profile {
          guard let records = try? loadBranchRecords(from: profile) else { continue }
          children = records
        } else {
          guard let profile = try branchProfile(for: childDirectory, opened: &opened) else {
            continue
          }
          guard let records = try? loadBranchRecords(from: profile) else { continue }
          children = records
        }
        pending.append((children, childDirectory.path))
      }
    }
    return collected
  }

  private func branchProfile(
    for directory: URL, opened: inout [String: ProfileStore]
  ) throws -> ProfileStore? {
    let path = directory.standardizedFileURL.path
    if let existing = opened[path] { return existing }
    guard let profile = try? ProfileStore.open(directory: directory) else { return nil }
    opened[path] = profile
    return profile
  }

  /// Report for one durable branch record, with the live page mapping and the pages that
  /// still need an explicit restore.
  private func branchInfo(for record: BranchRecord) -> BrowserBranchInfo {
    let attached = branchContexts[record.id]
    let pages = attached.flatMap { try? listPages(contextID: $0) } ?? []
    let map = Dictionary(uniqueKeysWithValues: zip(record.sourcePages, pages).map {
      (String($0.0.page), String($0.1.id.rawValue))
    })
    let restoreRequired = pages.compactMap { page -> String? in
      guard (try? lifecycleState(pageID: page.id)) == .discarded else { return nil }
      return String(page.id.rawValue)
    }
    return BrowserBranchInfo(
      id: record.id, name: record.name, contextID: attached,
      parentBranchID: record.parentBranchID, checkpointID: record.checkpointID,
      checkpoint: record.checkpoint, createdAt: record.createdAt, pageCount: pages.count,
      directory: record.directory, websiteDataStoreID: record.websiteDataStoreID,
      live: attached != nil, pageMap: map, restoreRequiredPages: restoreRequired,
      clonedState: BranchStateCatalog.cloned, bestEffortState: BranchStateCatalog.bestEffort,
      notClonedState: BranchStateCatalog.notCloned)
  }

  /// Deletes one branch from anywhere in the tree. The record is removed from the index of
  /// the profile that owns it (its parent), so a root caller can manage descendants, and a
  /// branch with children is still refused.
  public func deleteBranch(contextID: ContextID, branchID: BranchID) async throws {
    guard let context = contexts[contextID], let profile = context.profile else {
      if contexts[contextID] == nil { throw BrowserRuntimeError.contextNotFound(contextID) }
      throw BrowserRuntimeError.profileNotConfigured(contextID)
    }
    let tree = try loadBranchTree(from: profile, directory: profile.directory)
    guard let record = tree.first(where: { $0.id == branchID }) else {
      throw BranchError.notFound(branchID)
    }
    guard !tree.contains(where: { $0.parentBranchID == branchID }) else {
      throw BranchError.hasChildren(branchID)
    }
    let ownerDirectory = URL(fileURLWithPath: record.parentDirectory).standardizedFileURL
    let ownerProfile: ProfileStore?
    var openedOwner: ProfileStore?
    if ownerDirectory.path == profile.directory.standardizedFileURL.path {
      ownerProfile = profile
    } else if let attachedOwner = contexts.values.first(where: {
      $0.profile?.directory.standardizedFileURL.path == ownerDirectory.path
    }) {
      ownerProfile = attachedOwner.profile
    } else if FileManager.default.fileExists(atPath: ownerDirectory.path) {
      guard let store = try? ProfileStore.open(directory: ownerDirectory) else {
        throw BranchError.parentUnavailable(record.parentDirectory)
      }
      openedOwner = store
      ownerProfile = store
    } else {
      throw BranchError.parentUnavailable(record.parentDirectory)
    }
    defer { openedOwner?.close() }
    let attachedContext = branchContexts.removeValue(forKey: branchID)
    if let attachedContext {
      contextBranches[attachedContext] = nil
      try await destroyContext(attachedContext)
    }
    await purgeWebKitStore(identifier: record.websiteDataStoreID)
    if FileManager.default.fileExists(atPath: record.directory) {
      try FileManager.default.removeItem(atPath: record.directory)
    }
    if let ownerProfile {
      var ownerRecords = try loadBranchRecords(from: ownerProfile)
      ownerRecords.removeAll { $0.id == branchID }
      try saveBranchRecords(ownerRecords, to: ownerProfile)
    }
    // Created and discarded carry the same identity: the branch's own context while it was
    // attached, falling back to the caller's context for a dormant branch.
    await events.publish(
      .branchDiscarded(id: branchID.description),
      identity: BrowserEventIdentity(
        context: attachedContext ?? contextID, branch: branchID.description))
  }

  private func loadBranchRecords(from profile: ProfileStore) throws -> [BranchRecord] {
    guard let data = try profile.getKV(scope: BranchKV.scope, key: BranchKV.indexKey) else {
      return []
    }
    return try JSONDecoder().decode([BranchRecord].self, from: data)
  }

  private func saveBranchRecords(_ records: [BranchRecord], to profile: ProfileStore) throws {
    try profile.setKV(
      scope: BranchKV.scope, key: BranchKV.indexKey,
      value: try JSONEncoder().encode(records))
  }
}
