import Foundation
import Testing
@testable import AetherHumanUI

struct SessionArchiveTests {
    @Test func sessionRoundTripsThroughJSON() throws {
        let tabs = [
            BrowserSessionTab(id: UUID(), profileID: UUID(), title: "Gmail",
                              url: "https://mail.google.com/", isPinned: true),
            BrowserSessionTab(id: UUID(), profileID: UUID(), title: "New Tab",
                              url: nil, isPinned: false),
        ]
        let window = BrowserSessionWindow(
            id: UUID(), activeProfileID: tabs[0].profileID, arrangement: .sidebar,
            sidebarCollapsed: false,
            selectedByProfile: [tabs[0].profileID: tabs[0].id], tabs: tabs)
        let archive = BrowserSessionArchive(windows: [window])
        let data = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(BrowserSessionArchive.self, from: data)
        #expect(decoded == archive)
        #expect(decoded.windows[0].tabs[0].isPinned)
        #expect(decoded.windows[0].tabs[1].url == nil)
    }

    @Test func persistenceKeepsSessionKeySeparateFromArchive() {
        let suiteName = "aether.tests.session.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let archive = BrowserArchive(profiles: [BrowserProfile(name: "Personal")])
        BrowserPersistence.save(archive, defaults: defaults)
        #expect(BrowserPersistence.load(defaults: defaults).profiles.count == 1)
        #expect(BrowserPersistence.loadSession(defaults: defaults).windows.isEmpty)
        let session = BrowserSessionArchive(windows: [
            BrowserSessionWindow(id: UUID(), activeProfileID: UUID(), arrangement: .top,
                                 sidebarCollapsed: false, selectedByProfile: [:], tabs: [])
        ])
        BrowserPersistence.saveSession(session, defaults: defaults)
        #expect(BrowserPersistence.loadSession(defaults: defaults).windows.count == 1)
        #expect(BrowserPersistence.load(defaults: defaults).profiles.count == 1)
    }

    @MainActor @Test func searchStateTabsAreNotSerializedIntoTheSession() {
        let tab = BrowserTab(profileID: UUID())
        tab.loadState = .search("swift concurrency")
        tab.url = "https://example.com/"
        #expect(BrowserSessionTab(tab: tab) == nil)
        tab.loadState = .ready
        #expect(BrowserSessionTab(tab: tab) != nil)
    }
}

struct SearchLocalityTests {
    @Test func defaultLocalityIsSanFrancisco() {
        let locality = SearchLocality.sanFrancisco
        #expect(locality.countryCode == "US")
        #expect(locality.regionCode == "CA")
        #expect(locality.city == "San Francisco")
        #expect(locality.postalCode == "94158")
        #expect(locality.nearbyPostalCodes == ["94105", "94103", "94110"])
    }

    @MainActor @Test func localityPersistsIndependentlyOfRoute() {
        let suiteName = "aether.tests.locality.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = BrowserPreferences(defaults: defaults)
        #expect(preferences.searchLocality.city == "San Francisco")
        preferences.networkRoute = BrowserNetworkRoute(region: .newYork, enabled: true)
        #expect(preferences.searchLocality.city == "San Francisco")
        preferences.searchLocality.city = "Oakland"
        #expect(preferences.networkRoute.region == .newYork)
        let reloaded = BrowserPreferences(defaults: defaults)
        #expect(reloaded.searchLocality.city == "Oakland")
        #expect(reloaded.networkRoute.region == .newYork)
    }

    @Test func googleCarriesDocumentedRegionParameters() throws {
        let url = try #require(SearchProvider.google.searchURL(
            for: "swiftui layout", locality: .sanFrancisco))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "gl", value: "us")))
        #expect(items.contains(URLQueryItem(name: "q", value: "swiftui layout")))
        let plain = try #require(SearchProvider.google.searchURL(for: "swiftui layout"))
        let plainItems = URLComponents(url: plain, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(!plainItems.contains { $0.name == "gl" })
    }

    @Test func localityTermsAppendOnlyWhenEnabled() throws {
        let url = try #require(SearchProvider.duckDuckGo.searchURL(
            for: "coffee", locality: .sanFrancisco, localityTerms: true))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = items.first { $0.name == "q" }?.value ?? ""
        #expect(query.contains("San Francisco"))
        #expect(items.contains(URLQueryItem(name: "kl", value: "us-en")))
    }
}

struct KeychainContractTests {
    @Test func accountsAreNamespacedWithoutCollisions() {
        let first = UUID()
        let second = UUID()
        let a = AetherKeychain.credentialAccount(
            profileID: first, provider: "google", accountID: "user@example.com")
        let b = AetherKeychain.credentialAccount(
            profileID: second, provider: "google", accountID: "user@example.com")
        #expect(a != b)
        #expect(a.hasPrefix(first.uuidString + ":"))
        #expect(AetherKeychain.proxyCredentialAccount(endpointID: "ep-1") == "proxy:ep-1")
        #expect(AetherKeychain.service == "fun.aether.secure-storage")
    }

    @Test func keychainErrorsCarryReadableMessages() {
        #expect(AetherKeychainError.invalidData.message.contains("Keychain"))
        #expect(AetherKeychainError.unexpectedStatus(-25300).message.contains("-25300"))
    }
}

struct NetworkRouteTests {
    @Test func onlyConnectedRoutesClaimHiddenIP() {
        #expect(NetworkRouteStatus.connected.claimsHiddenIP)
        #expect(!NetworkRouteStatus.connecting.claimsHiddenIP)
        #expect(!NetworkRouteStatus.direct.claimsHiddenIP)
        #expect(!NetworkRouteStatus.unavailable.claimsHiddenIP)
        #expect(!NetworkRouteStatus.blocked.claimsHiddenIP)
        #expect(!NetworkRouteStatus.unknown.claimsHiddenIP)
        #expect(NetworkRouteStatus.direct.label == "Direct connection")
        #expect(NetworkRouteStatus.unavailable.label == "Remote exit unavailable")
    }

    @Test func routeDefaultsToDirectAndFailClosed() {
        let route = BrowserNetworkRoute.direct
        #expect(!route.enabled)
        #expect(route.region == .direct)
        #expect(route.failClosed)
    }

    @Test func allExitRegionsAreDistinctAndCodable() throws {
        let regions = AetherExitRegion.allCases
        #expect(Set(regions.map(\.rawValue)).count == regions.count)
        #expect(regions.count == 5)
        let data = try JSONEncoder().encode(AetherExitRegion.boston)
        #expect(try JSONDecoder().decode(AetherExitRegion.self, from: data) == .boston)
    }

    @Test func disabledRouteAndDirectResolveToTheSameConfiguredState() {
        let disabled = BrowserNetworkRoute(region: .sanFrancisco, enabled: false)
        #expect(disabled.region == .sanFrancisco)
        #expect(!disabled.enabled)
        #expect(BrowserNetworkRoute.direct.enabled == false)
    }

    @Test func expectedExitIPRoundTripsAndDefaultsToNil() throws {
        let endpoint = RouteEndpoint(
            host: "exit.example.com", port: 1080, region: .sanFrancisco,
            expectedExitIP: "203.0.113.10")
        let data = try JSONEncoder().encode(endpoint)
        #expect(try JSONDecoder().decode(RouteEndpoint.self, from: data) == endpoint)
        let legacy = """
            {"id":"ep-1","host":"exit.example.com","port":1080,"region":"San Francisco"}
            """.data(using: .utf8)!
        #expect(try JSONDecoder().decode(RouteEndpoint.self, from: legacy).expectedExitIP == nil)
    }

    @Test func persistedPreferencesNeverCarrySecrets() throws {
        let endpoint = RouteEndpoint(
            host: "exit.example.com", port: 1080, region: .newYork,
            expectedExitIP: "203.0.113.20")
        let route = BrowserNetworkRoute(
            region: .newYork, enabled: true, failClosed: true, endpointID: endpoint.id)
        for encoded in [
            try JSONEncoder().encode(endpoint), try JSONEncoder().encode(route),
            try JSONEncoder().encode([endpoint]),
        ] {
            let text = String(data: encoded, encoding: .utf8) ?? ""
            #expect(!text.localizedCaseInsensitiveContains("password"))
            #expect(!text.localizedCaseInsensitiveContains("username"))
            #expect(!text.localizedCaseInsensitiveContains("secret"))
            #expect(!text.localizedCaseInsensitiveContains("token"))
        }
    }
}
