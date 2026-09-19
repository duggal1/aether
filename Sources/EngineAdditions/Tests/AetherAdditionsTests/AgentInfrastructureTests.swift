import XCTest
import Foundation
import AetherAgentInfrastructure
import AetherResourceControl

final class AgentInfrastructureTests: XCTestCase {
    func testSessionIsolationAndRotation() async throws {
        let auth = SessionAuthority()
        let old = try await auth.create(session: "work", owner: "agent-a", allowed: [.inspect, .navigate])
        try await auth.check(session: "work", owner: "agent-a", permission: .inspect, generation: old.generation)
        do { try await auth.check(session: "work", owner: "agent-b", permission: .inspect); XCTFail("Isolation failed") }
        catch AuthorityError.forbidden {}
        do { try await auth.check(session: "work", owner: "agent-a", permission: .storage); XCTFail("Privilege boundary failed") }
        catch AuthorityError.forbidden {}
        let rotated = try await auth.rotate(session: "work", owner: "agent-a")
        XCTAssertNotEqual(rotated.generation, old.generation)
        do { try await auth.check(session: "work", owner: "agent-a", permission: .inspect, generation: old.generation); XCTFail("Old generation accepted") }
        catch AuthorityError.forbidden {}
    }

    func testJournalGapAndCursor() async {
        let journal = EventJournal(capacity: 2)
        await journal.append(session: "a", type: "one")
        await journal.append(session: "a", type: "two")
        await journal.append(session: "b", type: "three")
        let batch = await journal.replay(after: 0)
        XCTAssertTrue(batch.hasGap)
        XCTAssertEqual(batch.events.map(\.type), ["two", "three"])
        XCTAssertEqual(batch.nextCursor, 3)
    }

    func testDeduplication() async {
        let journal = CommandDeduplication()
        let payload = Data("payload".utf8)
        let response = Data("response".utf8)
        let first = await journal.begin(owner: "a", request: "r", fingerprint: payload)
        XCTAssertEqual(first, .execute)
        let during = await journal.begin(owner: "a", request: "r", fingerprint: payload)
        XCTAssertEqual(during, .inProgress)
        await journal.finish(owner: "a", request: "r", response: response)
        let cached = await journal.begin(owner: "a", request: "r", fingerprint: payload)
        XCTAssertEqual(cached, .cached(response))
        let conflicting = await journal.begin(owner: "a", request: "r", fingerprint: Data("other".utf8))
        XCTAssertEqual(conflicting, .payloadConflict)
    }

    func testOperationTransitions() async throws {
        let operations = OperationRegistry()
        try await operations.register(id: "1", owner: "agent", session: "s", kind: "navigate")
        _ = try await operations.transition(id: "1", owner: "agent", to: .running)
        let success = try await operations.transition(id: "1", owner: "agent", to: .succeeded)
        XCTAssertNotNil(success.finishedAt)
        do { _ = try await operations.transition(id: "1", owner: "agent", to: .running); XCTFail("Illegal transition") }
        catch OperationError.invalidTransition {}
    }
}

extension AgentInfrastructureTests {
    func testGatewayRejectsUnauthorizedAndReplaysSuccessfulRequests() async throws {
        let authority = SessionAuthority()
        let grant = try await authority.create(session: "s", owner: "a", allowed: [.inspect])
        let journal = EventJournal()
        let gateway = AgentGateway(authority: authority, journal: journal,
            deduplication: CommandDeduplication(), operations: OperationRegistry(),
            gate: ConcurrencyGate(capacity: 2),
            policy: CommandAccessPolicy(rules: ["page.inspect": .inspect, "page.navigate": .navigate]))
        let inspect = AgentInvocation(id: "request", owner: "a", session: "s", generation: grant.generation,
            method: "page.inspect", parameters: Data())
        let expected = Data("ok".utf8)
        let first = try await gateway.execute(inspect) { _ in expected }
        XCTAssertEqual(first, expected)
        let second = try await gateway.execute(inspect) { _ in Data("unexpected".utf8) }
        XCTAssertEqual(second, expected)
        let navigation = AgentInvocation(id: "other", owner: "a", session: "s", generation: grant.generation,
            method: "page.navigate", parameters: Data())
        do { _ = try await gateway.execute(navigation) { _ in expected }; XCTFail("Unauthorized navigation") }
        catch AuthorityError.forbidden {}
    }
}

extension AgentInfrastructureTests {
    func testMailboxRespectsOwner() async throws {
        let mailbox = AgentTaskMailbox(capacity: 2)
        try await mailbox.enqueue(AgentTask(id: "one", owner: "a", session: "s", action: "navigate"))
        let wrongOwner = await mailbox.take(owner: "b")
        XCTAssertNil(wrongOwner)
        let task = await mailbox.take(owner: "a")
        XCTAssertEqual(task?.id, "one")
        do { try await mailbox.complete(id: "one", owner: "b"); XCTFail("Wrong owner accepted") }
        catch MailboxError.wrongOwner {}
        try await mailbox.complete(id: "one", owner: "a")
    }
}
