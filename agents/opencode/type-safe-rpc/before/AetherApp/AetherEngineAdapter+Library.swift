import AetherHumanUI
import Foundation

extension AetherEngineAdapter: BrowserLibraryProviding {
  func loadLibrary(profileID: UUID) async throws -> BrowserProfileLibrary? {
    let context = try await context(for: profileID)
    let data = try await engine.runtime.checkpointValue(contextID: context, key: "human.library.v1")
    var library = try data.map { try JSONDecoder().decode(BrowserProfileLibrary.self, from: $0) }
    let actual = try await engine.runtime.listBookmarks(contextID: context)
    if !actual.isEmpty || library != nil {
      var bookmarks: [BrowserBookmark] = []
      for mark in actual {
        var value = library?.bookmarks.first { $0.url == mark.url }
          ?? BrowserBookmark(profileID: profileID, title: mark.title, url: mark.url)
        value.title = mark.title
        value.createdAt = Date(timeIntervalSince1970: mark.createdAt)
        bookmarks.append(value)
      }
      library = BrowserProfileLibrary(bookmarks: bookmarks, visits: library?.visits ?? [])
    }
    return library
  }

  func saveLibrary(profileID: UUID, library: BrowserProfileLibrary) async throws {
    let context = try await context(for: profileID)
    let existing = try await engine.runtime.listBookmarks(contextID: context)
    let desired = library.bookmarks.filter { $0.profileID == profileID }
    for item in existing where !desired.contains(where: { $0.url == item.url }) {
      if let url = URL(string: item.url) { _ = try await engine.runtime.removeBookmark(contextID: context, url: url) }
    }
    for item in desired {
      if let url = URL(string: item.url) {
        _ = try await engine.runtime.addBookmark(contextID: context, url: url, title: item.title)
      }
    }
    let data = try JSONEncoder().encode(library)
    try await engine.runtime.setCheckpoint(contextID: context, key: "human.library.v1", value: data)
    try await engine.runtime.checkpoint(contextID: context)
  }
}
