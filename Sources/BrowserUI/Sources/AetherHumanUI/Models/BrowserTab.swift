import Foundation
import Observation

@MainActor @Observable
public final class BrowserTab: Identifiable {
    public let id: UUID
    public var profileID: UUID
    public var enginePageID: String?
    public var title: String
    /// Search-port: user rename in place, survives quit. Displayed instead of title when non-empty.
    public var customTitle: String = ""
    /// Search-port: last time tab was looked at, for sleeping-tabs policy.
    public var lastActiveAt: Date = Date()
    /// Search-port: true after sleep (page released, snapshot kept). Wakes on select.
    public var isSleeping: Bool = false
    /// Search-port: per-tab private (nonPersistent). Never archived.
    public var isPrivateTab: Bool = false
    public var displayTitle: String { customTitle.isEmpty ? title : customTitle }
    public var url: String?
    public var isPinned: Bool = false
    public var isMuted = false
    @ObservationIgnored var muteAppliedURL: String?
    /// Resolved from the actual loaded page background; nil keeps neutral chrome.
    public var siteSurface: UInt? = nil
    /// Page theme metadata (`prefers-color-scheme`).
    public var sitePrefersDark: Bool? = nil
    /// Last committed page state, kept for boundary hysteresis so a page that
    /// sits near the light/dark threshold cannot flicker while it loads.
    public var surfaceAppearance: AetherSurfaceAppearance? = nil
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
    public var semanticSignals: BrowserSemanticSignals? = nil
    public var sessionState: BrowserSessionState? { semanticSignals?.sessionState }
    public var overlayKind: BrowserOverlayKind? { semanticSignals?.overlayKind }
    public var overlaySafeToDismissProbability: Double? { semanticSignals?.overlaySafeToDismissProbability }
    public var accessGateKind: BrowserAccessGateKind? { semanticSignals?.accessGateKind }
    public var phishingIdentityMismatchProbability: Double? {
        semanticSignals?.phishingIdentityMismatchProbability
    }
    public var fileUploadIntent: BrowserUploadIntent? { semanticSignals?.uploadIntent }
    public var semanticGroupID: String? { semanticSignals?.semanticGroupID }
    public var tabImportanceScore: Double? { semanticSignals?.tabImportanceScore }
    public init(id: UUID = UUID(), profileID: UUID, title: String = "New Tab", url: String? = nil) {
        self.id = id; self.profileID = profileID; self.title = title; self.url = url
    }
}
