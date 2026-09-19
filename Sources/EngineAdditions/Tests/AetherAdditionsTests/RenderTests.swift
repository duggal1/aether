import XCTest
import Foundation
import AetherRenderInfrastructure

final class RenderTests: XCTestCase {
    func testCapturePlanCompleteCoverage() {
        let plan = PageCapturePlan(contentHeight: 2500, viewport: CaptureViewport(width: 1280, height: 800), overlap: 100)
        XCTAssertEqual(plan.steps.first?.scrollY, 0)
        XCTAssertEqual(plan.steps.last?.scrollY, 1700)
        let total = plan.steps.map(\.contentRect.height).reduce(0, +)
        XCTAssertEqual(total, 2500)
    }

    func testCapturePlanShortPage() {
        let plan = PageCapturePlan(contentHeight: 200, viewport: CaptureViewport(width: 1280, height: 800))
        XCTAssertEqual(plan.steps.count, 1)
        XCTAssertEqual(plan.steps[0].contentRect.height, 200)
    }

    func testFrameJournalBounded() async {
        let journal = RenderFrameJournal(capacity: 2)
        let viewport = CaptureViewport(width: 10, height: 10)
        _ = await journal.commit(viewport: viewport, damage: [], layoutNanoseconds: 1, paintNanoseconds: 1, compositeNanoseconds: 1)
        _ = await journal.commit(viewport: viewport, damage: [], layoutNanoseconds: 1, paintNanoseconds: 1, compositeNanoseconds: 1)
        _ = await journal.commit(viewport: viewport, damage: [], layoutNanoseconds: 1, paintNanoseconds: 1, compositeNanoseconds: 1)
        let frames = await journal.since(0)
        XCTAssertEqual(frames.map(\.revision), [2, 3])
    }

    func testManifestStableJSON() throws {
        let manifest = DesignCaptureManifest(sourceURL: "https://example.com", viewport: CaptureViewport(width: 100, height: 100), documentHeight: 100, sections: [], assets: [], warnings: [], htmlPath: nil, stylesheetPaths: [])
        let text = try XCTUnwrap(String(data: manifest.json(), encoding: .utf8))
        XCTAssertTrue(text.contains("example.com"))
    }
}
