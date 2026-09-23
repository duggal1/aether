import EngineCore
import Foundation
import Testing
import WebKit
@testable import EngineRuntime

struct WebKitSessionPersistenceTests {
    private func marker(_ value: String = "session-alive") -> WebCookieInput {
        WebCookieInput(
            name: "aether_session_marker", value: value, domain: "fixture.test",
            path: "/", secure: false, httpOnly: false)
    }

    @Test @MainActor func markersSurviveFreshContextForSameProfile() async throws {
        let profile = UUID()
        try await WebKitCookieBridge.set(
            await WebKitContext(identifier: profile), input: marker())
        let reopened = await WebKitContext(identifier: profile)
        let cookies = try await WebKitCookieBridge.list(reopened)
        #expect(cookies.contains { $0.name == "aether_session_marker" && $0.value == "session-alive" })
    }

    @Test @MainActor func profilesAreIsolated() async throws {
        let personal = UUID()
        let work = UUID()
        try await WebKitCookieBridge.set(
            await WebKitContext(identifier: personal), input: marker())
        let workCookies = try await WebKitCookieBridge.list(await WebKitContext(identifier: work))
        #expect(!workCookies.contains { $0.name == "aether_session_marker" })
    }

    @Test @MainActor func ephemeralNeverSeesPermanentMarkers() async throws {
        let profile = UUID()
        try await WebKitCookieBridge.set(
            await WebKitContext(identifier: profile), input: marker("permanent"))
        let ephemeralCookies = try await WebKitCookieBridge.list(await WebKitContext.ephemeral())
        #expect(!ephemeralCookies.contains { $0.name == "aether_session_marker" })
        try await WebKitCookieBridge.set(await WebKitContext.ephemeral(), input: marker("transient"))
        let permanentCookies = try await WebKitCookieBridge.list(
            await WebKitContext(identifier: profile))
        #expect(!permanentCookies.contains { $0.value == "transient" })
    }

    @Test func runtimeCookieAPIsAreProfileScoped() async throws {
        let runtime = BrowserRuntime()
        let personal = try await runtime.createContext(name: "personal")
        let work = try await runtime.createContext(name: "work")
        try await runtime.setCookie(
            contextID: personal.id,
            cookie: CookieInfo(
                name: "aether_session_marker", value: "personal",
                domain: "fixture.test", path: "/"))
        let workCookies = try await runtime.listCookies(contextID: work.id)
        #expect(!workCookies.contains { $0.name == "aether_session_marker" })
        let personalCookies = try await runtime.listCookies(contextID: personal.id)
        #expect(personalCookies.contains { $0.value == "personal" })
        try await runtime.destroyContext(personal.id)
        try await runtime.destroyContext(work.id)
    }
}
