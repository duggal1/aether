import Foundation
import Network
import Testing
import WebKit
@testable import EngineRuntime

struct WebKitProxyIsolationTests {
    @Test @MainActor func unnamedContextsDoNotShareWebsiteData() {
        let first = WebKitStoreCache.shared.store(for: nil)
        let second = WebKitStoreCache.shared.store(for: nil)
        #expect(first !== second)
    }

    @Test @MainActor func profileStoresAreStablePerIdentifier() {
        let profileID = UUID()
        let first = WebKitStoreCache.shared.store(for: profileID)
        let second = WebKitStoreCache.shared.store(for: profileID)
        #expect(first === second)
        #expect(first !== WebKitStoreCache.shared.store(for: nil))
    }

    @Test @MainActor func ephemeralContextsGetIndependentStores() async {
        let left = await WebKitContext.ephemeral()
        let right = await WebKitContext.ephemeral()
        #expect(left.isEphemeral)
        #expect(right.isEphemeral)
        #expect(left.store !== right.store)
    }

    @Test @MainActor func proxyAppliesWithoutFailoverWhenFailClosed() async {
        let context = await WebKitContext.ephemeral()
        context.apply(proxy: WebProxyEndpoint(host: "127.0.0.1", port: 1080, failClosed: true))
        #expect(context.store.proxyConfigurations.count == 1)
        #expect(context.store.proxyConfigurations.first?.allowFailover == false)
        context.apply(proxy: nil)
        #expect(context.store.proxyConfigurations.isEmpty)
    }

    @Test @MainActor func failOpenEndpointAllowsFailover() async {
        let context = await WebKitContext.ephemeral()
        context.apply(proxy: WebProxyEndpoint(host: "127.0.0.1", port: 1080, failClosed: false))
        #expect(context.store.proxyConfigurations.first?.allowFailover == true)
    }

    @Test func runtimeStoresPendingProxyPerContext() async throws {
        let runtime = BrowserRuntime()
        let context = try await runtime.createContext(name: "proxy-test")
        let endpoint = WebProxyEndpoint(host: "exit.example.com", port: 1081, failClosed: true)
        try await runtime.configureWebProxy(contextID: context.id, endpoint: endpoint)
        #expect(await runtime.webProxyEndpoints[context.id] == endpoint)
        try await runtime.configureWebProxy(contextID: context.id, endpoint: nil)
        #expect(await runtime.webProxyEndpoints[context.id] == nil)
        try await runtime.destroyContext(context.id)
        #expect(await runtime.webProxyEndpoints[context.id] == nil)
    }

    @Test @MainActor func blackholeEndpointIsFailClosed() {
        #expect(WebProxyEndpoint.failClosedBlackhole.failClosed)
        #expect(WebProxyEndpoint.failClosedBlackhole.host == "127.0.0.1")
    }
}
