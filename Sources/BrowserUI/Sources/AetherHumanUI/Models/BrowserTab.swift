import Foundation
import Observation

@MainActor @Observable
public final class BrowserTab: Identifiable {
    public let id: UUID
    public var profileID: UUID
    public var enginePageID: String?
    public var title: String
    public var url: String?
    public var isPinned: Bool = false
    public var loadState: TabLoadState = .newTab
    public var canGoBack = false
    public var canGoForward = false
    public var isSecure = true
    public init(id: UUID = UUID(), profileID: UUID, title: String = "New Tab", url: String? = nil) {
        self.id = id; self.profileID = profileID; self.title = title; self.url = url
    }
}
