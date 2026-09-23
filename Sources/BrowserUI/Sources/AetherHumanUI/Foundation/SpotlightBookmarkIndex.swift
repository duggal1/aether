import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

public actor SpotlightBookmarkIndex {
    private let index = CSSearchableIndex(name: "AetherSavedPages")
    private var indexedIDs = Set<String>()
    private var initialized = false

    public init() {}

    public func update(bookmarks: [BrowserBookmark], enabled: Bool) async throws {
        if !initialized {
            try await deleteAll()
            initialized = true
        }
        guard enabled else {
            if !indexedIDs.isEmpty {
                try await deleteAll()
                indexedIDs.removeAll()
            }
            return
        }
        let desired = Set(bookmarks.map { $0.id.uuidString })
        let removed = Array(indexedIDs.subtracting(desired))
        if !removed.isEmpty {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                index.deleteSearchableItems(withIdentifiers: removed) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        }
        let items = bookmarks.compactMap { bookmark -> CSSearchableItem? in
            guard let url = URL(string: bookmark.url),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil else { return nil }
            let attributes = CSSearchableItemAttributeSet(contentType: .url)
            attributes.title = bookmark.title
            attributes.displayName = bookmark.title
            attributes.contentDescription = url.host
            attributes.keywords = [bookmark.folder, url.host ?? ""]
            let item = CSSearchableItem(uniqueIdentifier: bookmark.id.uuidString,
                                        domainIdentifier: bookmark.profileID.uuidString,
                                        attributeSet: attributes)
            item.expirationDate = .distantFuture
            return item
        }
        if !items.isEmpty {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                index.indexSearchableItems(items) { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
        }
        indexedIDs = desired
    }

    private func deleteAll() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteAllSearchableItems { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
