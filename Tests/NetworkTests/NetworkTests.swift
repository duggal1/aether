import Foundation
import Networking
import Testing

@Test func cookieJarScopesCookies() async {
  let jar = CookieJar()
  let url = URL(string: "https://example.com/app")!
  jar.absorb(setCookie: "session=abc; Path=/; Secure; HttpOnly", from: url)
  let header = jar.header(for: URL(string: "https://example.com/x")!)
  #expect(header == "session=abc")
  let other = jar.header(for: URL(string: "https://other.test/x")!)
  #expect(other == nil)
}

@Test func cacheStoresFreshResponses() async {
  let cache = HTTPCache(maximumBytes: 1024)
  let url = URL(string: "https://example.com")!
  let response = HTTPResponse(
    requestID: .init(rawValue: 1), url: url, statusCode: 200,
    headers: ["Cache-Control": "max-age=60"], body: Data("x".utf8))
  await cache.store(response)
  #expect(await cache.response(for: url)?.fromCache == true)
}

@Test func cookieJarStoresDirectCookies() async {
  let jar = CookieJar()
  let url = URL(string: "https://example.com/app")!
  jar.store(
    Cookie(name: "session", value: "abc", domain: "example.com", path: "/", secure: true))
  #expect(jar.header(for: url) == "session=abc")
  #expect(jar.all().count == 1)
}

@Test func cacheSnapshotPreservesStoredAt() async {
  let cache = HTTPCache(maximumBytes: 1024)
  let url = URL(string: "https://example.com")!
  let response = HTTPResponse(
    requestID: .init(rawValue: 1), url: url, statusCode: 200,
    headers: ["Cache-Control": "max-age=3600"], body: Data("x".utf8))
  await cache.store(response)
  let snapshots = await cache.snapshot()
  #expect(snapshots.count == 1)
  let warmed = HTTPCache(maximumBytes: 1024)
  await warmed.restore(snapshots[0])
  #expect(await warmed.response(for: url)?.fromCache == true)
  #expect(await warmed.totalBytes == 1)
}

@Test func sameSiteStrictBlocksCrossSiteSend() async {
  let jar = CookieJar()
  let url = URL(string: "https://a.example/")!
  await jar.absorb(setCookie: "s=1; SameSite=Strict", from: url)
  let cross = CookieRequestContext(
    topLevelHost: "b.example", method: "GET", isTopLevelNavigation: true)
  #expect(await jar.header(for: url, context: cross) == nil)
  let same = CookieRequestContext(
    topLevelHost: "a.example", method: "GET", isTopLevelNavigation: true)
  #expect(await jar.header(for: url, context: same) == "s=1")
}


@Test func cacheDoesNotStorePrivateOrCookieBearingResponses() async {
  let cache = HTTPCache(maximumBytes: 1024)
  let url = URL(string: "https://example.com/private")!
  for headers in [
    ["Cache-Control": "no-store, max-age=60"],
    ["Cache-Control": "private, max-age=60"],
    ["Cache-Control": "no-cache, max-age=60"],
    ["Cache-Control": "max-age=60", "Set-Cookie": "session=secret"],
    ["Cache-Control": "max-age=60", "Vary": "Cookie"],
    ["Cache-Control": "max-age=60", "Vary": "*"],
    [:]
  ] {
    await cache.store(HTTPResponse(
      requestID: .init(rawValue: 1), url: url, statusCode: 200,
      headers: headers, body: Data("private".utf8)))
    #expect(await cache.response(for: url) == nil)
  }
}

@Test func cacheHonorsExplicitFreshness() async {
  let cache = HTTPCache(maximumBytes: 1024)
  let url = URL(string: "https://example.com/public")!
  await cache.store(HTTPResponse(
    requestID: .init(rawValue: 1), url: url, statusCode: 200,
    headers: ["Cache-Control": "public, max-age=60"], body: Data("ok".utf8)))
  #expect(await cache.response(for: url)?.body == Data("ok".utf8))
}
