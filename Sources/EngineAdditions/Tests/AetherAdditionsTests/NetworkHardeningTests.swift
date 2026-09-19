import XCTest
import Foundation
import AetherNetworkHardening

final class NetworkHardeningTests: XCTestCase {
    func testCacheFreshnessAndValidators() {
        let policy = HTTPFreshness(headers: ["Cache-Control": "public, max-age=60, stale-while-revalidate=30", "ETag": "\"v2\""])
        XCTAssertTrue(policy.isFresh(age: 59))
        XCTAssertFalse(policy.isFresh(age: 60))
        XCTAssertEqual(policy.staleWhileRevalidate, 30)
        XCTAssertEqual(policy.revalidationHeaders()["If-None-Match"], "\"v2\"")
    }

    func testPrivateAndAuthorizedResponsesNotShared() {
        XCTAssertFalse(HTTPFreshness(headers: ["cache-control": "private, max-age=120"]).storable)
        XCTAssertFalse(HTTPFreshness(headers: ["cache-control": "max-age=120"], requestHasAuthorization: true).storable)
        XCTAssertTrue(HTTPFreshness(headers: ["cache-control": "public, max-age=120"], requestHasAuthorization: true).storable)
    }

    func testHSTSUpgradeAndExpiration() async throws {
        let registry = HSTSRegistry()
        let site = try XCTUnwrap(URL(string: "https://example.com/"))
        let now = Date(timeIntervalSince1970: 1_000_000)
        await registry.observe(url: site, headers: ["Strict-Transport-Security": "max-age=60; includeSubDomains"], now: now)
        let upgraded = await registry.upgrade(try XCTUnwrap(URL(string: "http://child.example.com/a")), now: now)
        XCTAssertEqual(upgraded.scheme, "https")
        let expired = await registry.upgrade(try XCTUnwrap(URL(string: "http://child.example.com/a")), now: now.addingTimeInterval(61))
        XCTAssertEqual(expired.scheme, "http")
    }

    func testHSTSDoesNotTrustInsecureResponses() async throws {
        let registry = HSTSRegistry()
        await registry.observe(url: try XCTUnwrap(URL(string: "http://example.com")), headers: ["Strict-Transport-Security": "max-age=300"])
        let upgraded = await registry.upgrade(try XCTUnwrap(URL(string: "http://example.com")))
        XCTAssertEqual(upgraded.scheme, "http")
    }

    func testByteRanges() throws {
        XCTAssertEqual(try HTTPByteRanges.parse("bytes=0-9,-3", size: 100), [HTTPByteRange(start: 0, end: 9), HTTPByteRange(start: 97, end: 99)])
        XCTAssertEqual(try HTTPByteRanges.parse("bytes=90-", size: 100), [HTTPByteRange(start: 90, end: 99)])
        XCTAssertThrowsError(try HTTPByteRanges.parse("bytes=100-200", size: 100))
    }

    func testDownloadFilenameSanitization() {
        XCTAssertEqual(DownloadName.suggested(from: "attachment; filename=\"../../hello.txt\""), "hello.txt")
        XCTAssertEqual(DownloadName.suggested(from: "attachment; filename*=UTF-8''hello%20world.txt"), "hello world.txt")
    }
}

extension NetworkHardeningTests {
    func testReferrerPolicySuppressesCrossOriginPathAndDowngrade() throws {
        let source = try XCTUnwrap(URL(string: "https://user:password@example.com/private?a=1#section"))
        let crossOrigin = try XCTUnwrap(URL(string: "https://other.example/path"))
        let downgrade = try XCTUnwrap(URL(string: "http://other.example/path"))
        XCTAssertEqual(ReferrerPolicy.strictOriginWhenCrossOrigin.value(source: source, destination: crossOrigin), "https://example.com/")
        XCTAssertNil(ReferrerPolicy.strictOriginWhenCrossOrigin.value(source: source, destination: downgrade))
        XCTAssertNil(ReferrerPolicy.noReferrer.value(source: source, destination: crossOrigin))
    }

    func testNoSniffBlocksWrongScriptMime() {
        XCTAssertThrowsError(try ResponseContentGuard.validate(status: 200,
            headers: ["X-Content-Type-Options": "nosniff", "Content-Type": "text/html"], destination: .script))
        XCTAssertNoThrow(try ResponseContentGuard.validate(status: 200,
            headers: ["X-Content-Type-Options": "nosniff", "Content-Type": "text/javascript"], destination: .script))
    }

    func testVaryStarNotReusable() {
        let policy = HTTPFreshness(headers: ["Cache-Control": "public,max-age=100", "Vary": "*"])
        XCTAssertFalse(policy.storable)
    }
}
