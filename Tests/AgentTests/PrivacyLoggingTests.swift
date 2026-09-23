import AgentProtocol
import BrowserEngine
import EngineCore
import Foundation
import Testing
@testable import EngineRuntime

struct PrivacyLoggingTests {
    private func failingResponseMessages(_ responses: [AgentResponse]) -> [String] {
        responses.compactMap(\.error?.message)
    }

    @Test func cookieValuesNeverLeakIntoErrorsOrUnrelatedResults() async throws {
        let canary = "canary-\(UUID().uuidString)"
        let engine = NativeBrowserEngine()
        let context = await engine.runtime.createContext(name: "privacy-audit")
        try await engine.runtime.setCookie(
            contextID: context.id,
            cookie: CookieInfo(
                name: "session", value: canary, domain: "fixture.test", path: "/"))
        let dispatcher = AgentCommandDispatcher(engine: engine)
        let failures = [
            await dispatcher.handle(
                AgentRequest(method: "page.list", params: ["context": .number(9_999_999)])),
            await dispatcher.handle(
                AgentRequest(method: "context.destroy", params: ["context": .number(9_999_999)])),
            await dispatcher.handle(
                AgentRequest(method: "page.metrics", params: ["page": .number(9_999_999)])),
            await dispatcher.handle(AgentRequest(method: "no.such.method")),
        ]
        #expect(!failingResponseMessages(failures).isEmpty)
        for message in failingResponseMessages(failures) {
            #expect(!message.contains(canary))
        }
        let listed = await dispatcher.handle(AgentRequest(method: "context.list"))
        let stats = await dispatcher.handle(AgentRequest(method: "fleet.stats"))
        for response in [listed, stats] {
            if let result = response.result,
                let encoded = String(data: try JSONEncoder().encode(result), encoding: .utf8) {
                #expect(!encoded.contains(canary))
            }
        }
        try await engine.runtime.destroyContext(context.id)
    }

    @Test func cookieListingStaysScopedToItsOwnContext() async throws {
        let engine = NativeBrowserEngine()
        let owner = await engine.runtime.createContext(name: "owner")
        let stranger = await engine.runtime.createContext(name: "stranger")
        try await engine.runtime.setCookie(
            contextID: owner.id,
            cookie: CookieInfo(
                name: "session", value: "owner-secret", domain: "fixture.test", path: "/"))
        let dispatcher = AgentCommandDispatcher(engine: engine)
        let response = await dispatcher.handle(
            AgentRequest(
                method: "context.cookies",
                params: ["context": .number(Double(stranger.id.rawValue))]))
        if let result = response.result,
            let encoded = String(data: try JSONEncoder().encode(result), encoding: .utf8) {
            #expect(!encoded.contains("owner-secret"))
        } else {
            Issue.record("expected a scoped cookie result for the stranger context")
        }
        try await engine.runtime.destroyContext(owner.id)
        try await engine.runtime.destroyContext(stranger.id)
    }
}
