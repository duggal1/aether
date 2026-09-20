import AetherHumanUI
import Foundation

extension AetherEngineAdapter: BrowserProfileManaging {
  func deleteProfile(profileID: UUID) async throws {
    guard let id = contexts.removeValue(forKey: profileID) else { return }
    let owned = try await engine.runtime.listPages(contextID: id)
    for page in owned { await close(pageID: page.id.description) }
    try await engine.destroyContext(id)
    let directory = profileDirectory.appendingPathComponent(profileID.uuidString, isDirectory: true)
    if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
  }

  func restoredPages(profileID: UUID) async throws -> [EnginePageSnapshot] {
    guard !restoredProfiles.contains(profileID) else { return [] }
    restoredProfiles.insert(profileID)
    let context = try await context(for: profileID)
    let existing = try await engine.runtime.listPages(contextID: context)
    var restored: [EnginePageSnapshot] = []
    for page in existing where pages[page.id.description] == nil {
      let id = page.id.description
      pages[id] = page.id
      restored.append(EnginePageSnapshot(id: id, url: page.url?.absoluteString,
        title: page.title.isEmpty ? (page.url?.host ?? "Restored tab") : page.title,
        canGoBack: false, canGoForward: false, isSecure: page.url?.scheme == "https"))
    }
    return restored
  }
}


extension AetherEngineAdapter: BrowserPageActivating {
  func activate(pageID: String) async throws {
    guard surfaces[pageID] == nil else { return }
    let id = try page(pageID)
    _ = try await engine.runtime.restorePage(pageID: id)
    surfaces[pageID] = try await engine.runtime.webSurface(pageID: id)
  }
}
