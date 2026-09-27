import Foundation
import Observation

@MainActor @Observable
public final class BrowserPreferences {
    @ObservationIgnored private let defaults: UserDefaults
    public var arrangement: TabArrangement { didSet { save() } }
    public var appearance: AetherAppearance { didSet { save() } }
    public var provider: SearchProvider { didSet { save() } }
    public var restoreWindows: Bool { didSet { save() } }
    public var floatVideoWhenSwitchingTabs: Bool { didSet { save() } }
    public var floatVideoWhenSwitchingApps: Bool { didSet { save() } }
    public var showFavorites: Bool { didSet { save() } }
    public var showFullAddress: Bool { didSet { save() } }
    public var showSearchSuggestions: Bool { didSet { save() } }
    public var providerSuggestions: Bool { didSet { save() } }
    public var spotlightSavedPages: Bool { didSet { save() } }
    public var sidebarWidth: Double { didSet { save() } }
    public var transientSidebarWidth: Double?
    public var downloadFolder: String { didSet { save() } }
    public var privacy: BrowserPrivacyPolicy { didSet { save() } }
    public var typeSafeAPIKey: String { didSet { save() } }
    public var search1APIKey: String { didSet { save() } }
    public var progressColor: AetherProgressColor { didSet { save() } }
    public var customSearchTemplate: String { didSet { save() } }
    public var showBookmarksBar: Bool { didSet { save() } }
    public var showStatusLine: Bool { didSet { save() } }
    public var askWhereOnDownload: Bool { didSet { save() } }
    public var sleepTabsEnabled: Bool { didSet { save() } }
    public var peekOnShiftClick: Bool { didSet { save() } }
    public var searchLocality: SearchLocality { didSet { save() } }
    public var localityQueryTerms: Bool { didSet { save() } }
    public var networkRoute: BrowserNetworkRoute { didSet { save() } }
    public var routeEndpoints: [RouteEndpoint] { didSet { save() } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        arrangement = TabArrangement(rawValue: defaults.string(forKey: "aether.tabs") ?? "") ?? .top
        appearance = AetherAppearance(rawValue: defaults.string(forKey: "aether.appearance") ?? "") ?? .system
        // Jev is the browser's search intelligence, not a replacement for a
        // search engine: it judges intent and relevance, Search1API retrieves,
        // and Google stands behind it as the selectable provider and the
        // fallback. Defaulting away from Jev would leave only the retrieval
        // half of that pipeline. A stored rawValue still wins, so an explicit
        // choice is never overridden.
        provider = SearchProvider(rawValue: defaults.string(forKey: "aether.provider") ?? "") ?? .jev
        restoreWindows = defaults.object(forKey: "aether.restore.v2") as? Bool ?? false
        floatVideoWhenSwitchingTabs = defaults.object(forKey: "aether.float.tabs") as? Bool ?? true
        floatVideoWhenSwitchingApps = defaults.object(forKey: "aether.float.apps") as? Bool ?? false
        showFavorites = defaults.object(forKey: "aether.favorites") as? Bool ?? true
        showFullAddress = defaults.object(forKey: "aether.fullAddress") as? Bool ?? false
        showSearchSuggestions = defaults.object(forKey: "aether.suggest") as? Bool ?? true
        providerSuggestions = defaults.object(forKey: "aether.suggest.web") as? Bool ?? true
        spotlightSavedPages = defaults.object(forKey: "aether.search.spotlight") as? Bool ?? false
        sidebarWidth = max(188, min(324, defaults.object(forKey: "aether.sidebarWidth") as? Double ?? 190))
        downloadFolder = defaults.string(forKey: "aether.downloads") ?? "Downloads"
        privacy = BrowserPrivacyPolicy(
            blockAds: defaults.object(forKey: "aether.blockAds") as? Bool ?? true,
            blockTrackers: defaults.object(forKey: "aether.blockTrackers") as? Bool ?? true,
            handleCookieBanners: defaults.object(forKey: "aether.cookieBanners") as? Bool ?? true
        )
        typeSafeAPIKey = defaults.string(forKey: "aether.jev.typesafe") ?? ""
        search1APIKey = defaults.string(forKey: "aether.jev.search1") ?? ""
        progressColor = AetherProgressColor(rawValue: defaults.string(forKey: "aether.progressColor") ?? "") ?? .neutral
        customSearchTemplate = defaults.string(forKey: "aether.search.custom") ?? ""
        showBookmarksBar = defaults.object(forKey: "aether.bookmarksBar") as? Bool ?? false
        showStatusLine = defaults.object(forKey: "aether.statusLine") as? Bool ?? false
        askWhereOnDownload = defaults.object(forKey: "aether.downloads.ask") as? Bool ?? false
        sleepTabsEnabled = defaults.object(forKey: "aether.tabs.sleep") as? Bool ?? true
        peekOnShiftClick = defaults.object(forKey: "aether.links.peek") as? Bool ?? false
        if let data = defaults.data(forKey: "aether.searchLocality"),
           let decoded = try? JSONDecoder().decode(SearchLocality.self, from: data) {
            searchLocality = decoded
        } else {
            searchLocality = .sanFrancisco
        }
        localityQueryTerms = defaults.object(forKey: "aether.searchLocality.terms") as? Bool ?? false
        if let data = defaults.data(forKey: "aether.networkRoute"),
           let decoded = try? JSONDecoder().decode(BrowserNetworkRoute.self, from: data) {
            networkRoute = decoded
        } else {
            networkRoute = .direct
        }
        if let data = defaults.data(forKey: "aether.routeEndpoints"),
           let decoded = try? JSONDecoder().decode([RouteEndpoint].self, from: data) {
            routeEndpoints = decoded
        } else {
            routeEndpoints = []
        }
    }

    public func endpoint(for region: AetherExitRegion) -> RouteEndpoint? {
        if let id = networkRoute.endpointID, let exact = routeEndpoints.first(where: { $0.id == id }) {
            return exact
        }
        return routeEndpoints.first(where: { $0.region == region })
    }
    private func save() {
        defaults.set(arrangement.rawValue, forKey: "aether.tabs")
        defaults.set(appearance.rawValue, forKey: "aether.appearance")
        defaults.set(provider.rawValue, forKey: "aether.provider")
        defaults.set(restoreWindows, forKey: "aether.restore.v2")
        defaults.set(floatVideoWhenSwitchingTabs, forKey: "aether.float.tabs")
        defaults.set(floatVideoWhenSwitchingApps, forKey: "aether.float.apps")
        defaults.set(showFavorites, forKey: "aether.favorites")
        defaults.set(showFullAddress, forKey: "aether.fullAddress")
        defaults.set(showSearchSuggestions, forKey: "aether.suggest")
        defaults.set(providerSuggestions, forKey: "aether.suggest.web")
        defaults.set(spotlightSavedPages, forKey: "aether.search.spotlight")
        defaults.set(sidebarWidth, forKey: "aether.sidebarWidth")
        defaults.set(downloadFolder, forKey: "aether.downloads")
        defaults.set(privacy.blockAds, forKey: "aether.blockAds")
        defaults.set(privacy.blockTrackers, forKey: "aether.blockTrackers")
        defaults.set(privacy.handleCookieBanners, forKey: "aether.cookieBanners")
        defaults.set(typeSafeAPIKey, forKey: "aether.jev.typesafe")
        defaults.set(search1APIKey, forKey: "aether.jev.search1")
        defaults.set(progressColor.rawValue, forKey: "aether.progressColor")
        defaults.set(customSearchTemplate, forKey: "aether.search.custom")
        defaults.set(showBookmarksBar, forKey: "aether.bookmarksBar")
        defaults.set(showStatusLine, forKey: "aether.statusLine")
        defaults.set(askWhereOnDownload, forKey: "aether.downloads.ask")
        defaults.set(sleepTabsEnabled, forKey: "aether.tabs.sleep")
        defaults.set(peekOnShiftClick, forKey: "aether.links.peek")
        if let data = try? JSONEncoder().encode(searchLocality) { defaults.set(data, forKey: "aether.searchLocality") }
        defaults.set(localityQueryTerms, forKey: "aether.searchLocality.terms")
        if let data = try? JSONEncoder().encode(networkRoute) { defaults.set(data, forKey: "aether.networkRoute") }
        if let data = try? JSONEncoder().encode(routeEndpoints) { defaults.set(data, forKey: "aether.routeEndpoints") }
    }

    public func setEndpoint(_ endpoint: RouteEndpoint) {
        routeEndpoints.removeAll { $0.region == endpoint.region }
        routeEndpoints.append(endpoint)
        save()
    }

    public func forgetEndpoint(region: AetherExitRegion) {
        routeEndpoints.removeAll { $0.region == region }
        if networkRoute.region == region {
            networkRoute = .direct
        }
        save()
    }
}
