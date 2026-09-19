import XCTest
import AetherResourceControl

final class ResourceTests: XCTestCase {
    func testBudgetAndRelease() async throws {
        let ledger = ResourceLedger(limits: ResourceLimits(bytes: [.gpuMemory: 100]))
        let first = try await ledger.reserve(70, kind: .gpuMemory)
        do {
            _ = try await ledger.reserve(40, kind: .gpuMemory)
            XCTFail("Expected resource limit")
        } catch ResourceError.capacityExceeded(.gpuMemory) {}
        try await ledger.release(first)
        let next = try await ledger.reserve(100, kind: .gpuMemory)
        let snapshot = await ledger.snapshot()
        XCTAssertEqual(snapshot.used[.gpuMemory], 100)
        XCTAssertEqual(snapshot.utilization(.gpuMemory), 1)
        try await ledger.release(next)
    }

    func testDuplicateReleaseIsError() async throws {
        let ledger = ResourceLedger(limits: ResourceLimits(bytes: [.decodedImages: 10]))
        let reservation = try await ledger.reserve(3, kind: .decodedImages)
        try await ledger.release(reservation)
        do { try await ledger.release(reservation); XCTFail("Expected double-free rejection") }
        catch ResourceError.unknownReservation {}
    }

    func testFleetPrefersOldUnpinnedPages() {
        let pages = [
            FleetPage(id: "recent", owner: "a", state: .active, estimatedBytes: 100, importance: 10, lastUsedTick: 20),
            FleetPage(id: "old", owner: "b", state: .active, estimatedBytes: 100, importance: 0, lastUsedTick: 1),
            FleetPage(id: "pinned", owner: "c", state: .active, estimatedBytes: 100, pinned: true)
        ]
        let plan = FleetPolicy(budgetBytes: 220).plan(pages)
        XCTAssertEqual(plan.transitions.first?.pageID, "old")
        XCTAssertEqual(plan.unmetBytes, 0)
    }

    func testFleetAdmitsThatPressureMayBeUnmet() {
        let pages = [FleetPage(id: "keep", owner: "a", state: .active, estimatedBytes: 100, pinned: true)]
        let plan = FleetPolicy(budgetBytes: 30).plan(pages)
        XCTAssertEqual(plan.unmetBytes, 70)
    }

    func testConcurrencyGate() async throws {
        let gate = ConcurrencyGate(capacity: 1)
        try await gate.enter()
        let first = await gate.snapshot()
        XCTAssertEqual(first.active, 1)
        await gate.leave()
        let last = await gate.snapshot()
        XCTAssertEqual(last.active, 0)
    }
}
