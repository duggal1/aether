import Foundation
import Testing
@testable import AetherHumanUI

struct AddressResolverTests {
    @Test func validHTTPSAddress() {
        #expect(AddressResolver.resolve("https://github.com/duggal1/aether")?.host == "github.com")
    }
    @Test func bareDomain() {
        #expect(AddressResolver.resolve("github.com")?.absoluteString == "https://github.com")
    }
    @Test func searchQuery() {
        let url = AddressResolver.resolve("Swift native browser", provider: .google)
        #expect(url?.host == "www.google.com")
        #expect(url?.query?.contains("Swift") == true)
    }
    @Test func alternateSearchProvider() {
        #expect(AddressResolver.resolve("swift", provider: .duckDuckGo)?.host == "duckduckgo.com")
    }
    @Test func emptyInput() {
        #expect(AddressResolver.resolve("  ") == nil)
    }

    private func components(_ url: URL?) throws -> URLComponents {
        let resolved = try #require(url)
        return try #require(URLComponents(url: resolved, resolvingAgainstBaseURL: false))
    }

    private func value(_ url: URL?, _ name: String) throws -> String? {
        try components(url).queryItems?.first { $0.name == name }?.value
    }

    @Test func googleSearchURLShape() throws {
        let url = AddressResolver.resolve("SwiftUI Liquid Glass", provider: .google)
        #expect(url?.host == "www.google.com")
        #expect(url?.path == "/search")
        #expect(try value(url, "q") == "SwiftUI Liquid Glass")
        #expect(try value(url, "udm") == nil)
    }

    @Test func googleAIModeRouting() throws {
        let url = AddressResolver.resolve("WebKit performance", provider: .googleAI)
        #expect(url?.host == "www.google.com")
        #expect(url?.path == "/search")
        #expect(try value(url, "q") == "WebKit performance")
        #expect(try value(url, "udm") == "50")
    }

    @Test func queryEncodingIsExact() throws {
        let query = "a&b+c#d?e=f 100% ünïcode"
        let url = AddressResolver.resolve(query, provider: .google)
        #expect(try value(url, "q") == query)
        #expect(url?.absoluteString.contains("&b") == false)
        #expect(url?.absoluteString.contains("#") == false)
    }

    @Test func providerHomepages() {
        #expect(SearchProvider.googleAI.homepage.absoluteString == "https://www.google.com/ai")
        #expect(SearchProvider.google.homepage.absoluteString == "https://www.google.com/")
    }

    @Test func persistedProviderIdentitiesAreStable() {
        let stored = ["Google", "Google AI Mode", "DuckDuckGo", "Bing", "Brave"]
        #expect(Array(SearchProvider.allCases.map(\.rawValue).prefix(stored.count)) == stored)
        #expect(SearchProvider.allCases.contains(.jev))
        #expect(SearchProvider(rawValue: "Google AI Mode") == .googleAI)
        #expect(SearchProvider(rawValue: "Jev") == .jev)
    }

    @Test func jevProviderRoutesThroughIntelligenceInsteadOfAURL() {
        #expect(SearchProvider.jev.usesIntelligence)
        #expect(SearchProvider.jev.searchEndpoint == nil)
        #expect(SearchProvider.jev.searchURL(for: "apple") == nil)
        #expect(SearchProvider.google.usesIntelligence == false)
    }

    @Test func directURLClassificationStaysDeterministic() {
        #expect(AddressResolver.directURL("apple.com")?.absoluteString == "https://apple.com")
        #expect(AddressResolver.directURL("https://apple.com/x")?.host == "apple.com")
        #expect(AddressResolver.directURL("apple") == nil)
        #expect(AddressResolver.directURL("two words") == nil)
    }
}
