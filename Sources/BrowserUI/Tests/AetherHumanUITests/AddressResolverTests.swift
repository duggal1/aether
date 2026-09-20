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
}
