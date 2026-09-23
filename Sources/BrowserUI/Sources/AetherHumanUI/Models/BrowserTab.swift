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
    /// Resolved from the actual loaded page background; nil keeps neutral chrome.
    public var siteSurface: UInt? = nil
    /// Page theme metadata (`prefers-color-scheme`).
    public var sitePrefersDark: Bool? = nil
    /// Last committed chrome appearance, kept for boundary hysteresis.
    public var chromeAppearance: AetherChromeAppearance? = nil
    public var loadState: TabLoadState = .newTab
    public var loadProgress: Double = 0
    public var contentReady = false
    public var paintReady = true
    public var isLoading = false
    public var pendingURL: String?
    public var canGoBack = false
    public var canGoForward = false
    public var isSecure = true
    public var needsRestoreLoad = false
    public init(id: UUID = UUID(), profileID: UUID, title: String = "New Tab", url: String? = nil) {
        self.id = id; self.profileID = profileID; self.title = title; self.url = url
    }
}
