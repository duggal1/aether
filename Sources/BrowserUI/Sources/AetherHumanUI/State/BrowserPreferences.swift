import Foundation
import Observation

@MainActor @Observable
public final class BrowserPreferences {
    @ObservationIgnored private let defaults: UserDefaults
    public var arrangement: TabArrangement { didSet { save() } }
    public var appearance: AetherAppearance { didSet { save() } }
    public var provider: SearchProvider { didSet { save() } }
    public var restoreWindows: Bool { didSet { save() } }
    public var showFavorites: Bool { didSet { save() } }
    public var showFullAddress: Bool { didSet { save() } }
    public var sidebarWidth: Double { didSet { save() } }
    public var downloadFolder: String { didSet { save() } }
    public var privacy: BrowserPrivacyPolicy { didSet { save() } }
    public var progressColor: AetherProgressColor { didSet { save() } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        arrangement = TabArrangement(rawValue: defaults.string(forKey: "aether.tabs") ?? "") ?? .top
        appearance = AetherAppearance(rawValue: defaults.string(forKey: "aether.appearance") ?? "") ?? .system
        provider = SearchProvider(rawValue: defaults.string(forKey: "aether.provider") ?? "") ?? .google
        restoreWindows = defaults.object(forKey: "aether.restore") as? Bool ?? true
        showFavorites = defaults.object(forKey: "aether.favorites") as? Bool ?? true
        showFullAddress = defaults.object(forKey: "aether.fullAddress") as? Bool ?? false
        sidebarWidth = max(188, min(324, defaults.object(forKey: "aether.sidebarWidth") as? Double ?? 226))
        downloadFolder = defaults.string(forKey: "aether.downloads") ?? "Downloads"
        privacy = BrowserPrivacyPolicy(
            blockAds: defaults.object(forKey: "aether.blockAds") as? Bool ?? true,
            blockTrackers: defaults.object(forKey: "aether.blockTrackers") as? Bool ?? true,
            handleCookieBanners: defaults.object(forKey: "aether.cookieBanners") as? Bool ?? true
        )
        progressColor = AetherProgressColor(rawValue: defaults.string(forKey: "aether.progressColor") ?? "") ?? .violet
    }
    private func save() {
        defaults.set(arrangement.rawValue, forKey: "aether.tabs")
        defaults.set(appearance.rawValue, forKey: "aether.appearance")
        defaults.set(provider.rawValue, forKey: "aether.provider")
        defaults.set(restoreWindows, forKey: "aether.restore")
        defaults.set(showFavorites, forKey: "aether.favorites")
        defaults.set(showFullAddress, forKey: "aether.fullAddress")
        defaults.set(sidebarWidth, forKey: "aether.sidebarWidth")
        defaults.set(downloadFolder, forKey: "aether.downloads")
        defaults.set(privacy.blockAds, forKey: "aether.blockAds")
        defaults.set(privacy.blockTrackers, forKey: "aether.blockTrackers")
        defaults.set(privacy.handleCookieBanners, forKey: "aether.cookieBanners")
        defaults.set(progressColor.rawValue, forKey: "aether.progressColor")
    }
}
