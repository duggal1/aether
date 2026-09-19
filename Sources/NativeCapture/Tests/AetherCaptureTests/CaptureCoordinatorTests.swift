import Foundation
import Testing
@testable import AetherCapture

private func captureKit(
    _ session: FixtureCaptureSession, into destination: URL, options: CaptureOptions = fixtureOptions()
) async throws -> CaptureResult {
    try await CaptureCoordinator(engine: FixtureCaptureEngine(session: session), encoder: FixtureImageEncoder())
        .capture(URL(string: "https://fixture.test/start")!, into: destination, options: options)
}

private func withCaptureParent(_ body: (URL) async throws -> Void) async throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: parent) }
    try await body(parent)
}

private func decodeManifest(_ destination: URL) throws -> CaptureManifest {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(
        CaptureManifest.self, from: Data(contentsOf: destination.appendingPathComponent("manifest.json")))
}

@Test func completeKitManifestAndExactCompositeRows() async throws {
    try await withCaptureParent { parent in
        let destination = parent.appendingPathComponent("kit")
        let session = FixtureCaptureSession()
        let result = try await captureKit(session, into: destination)
        let manifest = try decodeManifest(destination)
        #expect(manifest.finalURL == "https://fixture.test/final")
        #expect(!manifest.truncated)
        #expect(manifest.screenshots.reduce(0) { $0 + $1.pixelHeight } == 240)
        var covered = 0.0
        for tile in manifest.screenshots {
            #expect(tile.cssY == covered)
            covered += tile.cssHeight
            #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent(tile.file).path))
        }
        #expect(covered == 240)
        let fullPage = try #require(result.manifest.fullPage)
        let bytes = try Data(contentsOf: destination.appendingPathComponent(fullPage))
        for row in 0..<240 { #expect(bytes[row * 400] == UInt8(row % 256)) }
        #expect(manifest.sections.count == 1)
        #expect(!manifest.sections[0].screenshotParts.isEmpty)
        for part in manifest.sections[0].screenshotParts {
            let data = try Data(contentsOf: destination.appendingPathComponent(part))
            #expect(data[1] == 10)
            #expect(data.count % (80 * 4) == 0)
        }
        #expect(manifest.assets.map(\.status) == ["saved", "saved", "uncached-or-oversize"])
        for asset in manifest.assets where asset.file != nil {
            let file = try #require(asset.file)
            let data = try Data(contentsOf: destination.appendingPathComponent(file))
            #expect(data == Data(repeating: 42, count: 8))
        }
        for file in ["website.html", "styles/index.json", "styles/0001.css", "computed-styles.json", "sections.json", "design-reference.md"] {
            let data = try Data(contentsOf: destination.appendingPathComponent(file))
            #expect(data.count > 0)
        }
        let closed = await session.closed
        #expect(closed)
    }
}

@Test func warmPassDiscoversGrowthBeforeSnapshot() async throws {
    try await withCaptureParent { parent in
        let session = FixtureCaptureSession(height: 160, grows: true)
        let result = try await captureKit(session, into: parent.appendingPathComponent("kit"))
        #expect(result.manifest.documentCSSHeight == 400)
        #expect(!result.manifest.truncated)
        let height = await session.snapshotHeight
        let y = await session.snapshotY
        #expect(height == 400)
        #expect(y == 0)
    }
}

@Test func heightAndCompositeBudgets() async throws {
    try await withCaptureParent { parent in
        var options = fixtureOptions()
        options.maximumDocumentCSSHeight = 160
        options.fullPageMaximumPixels = 100
        let result = try await captureKit(FixtureCaptureSession(), into: parent.appendingPathComponent("kit"), options: options)
        #expect(result.manifest.truncated)
        #expect(result.manifest.fullPage == nil)
        #expect(result.manifest.screenshots.reduce(0) { $0 + $1.cssHeight } == 160)
        #expect(result.manifest.warnings.contains { $0.code == "height-limit" })
    }
}

@Test func stepLimitReportsIncompleteCapture() async throws {
    try await withCaptureParent { parent in
        var options = fixtureOptions()
        options.maximumScrollSteps = 1
        let result = try await captureKit(FixtureCaptureSession(), into: parent.appendingPathComponent("kit"), options: options)
        #expect(result.manifest.truncated)
        #expect(result.manifest.warnings.contains { $0.code == "incomplete-capture" })
    }
}

@Test func stalledScrollReportsIncompleteCapture() async throws {
    try await withCaptureParent { parent in
        let result = try await captureKit(FixtureCaptureSession(fault: .stalled), into: parent.appendingPathComponent("kit"))
        #expect(result.manifest.truncated)
        #expect(result.manifest.screenshots.count == 1)
    }
}

@Test func assetBudgetsAreHonored() async throws {
    try await withCaptureParent { parent in
        var options = fixtureOptions()
        options.maximumAssetBytes = 8
        let result = try await captureKit(FixtureCaptureSession(), into: parent.appendingPathComponent("kit"), options: options)
        #expect(result.manifest.assets.map(\.status) == ["saved", "total-byte-budget", "total-byte-budget"])
    }
}

@Test func oversizeAssetsAreNotWritten() async throws {
    try await withCaptureParent { parent in
        var options = fixtureOptions()
        options.maximumSingleAssetBytes = 4
        let result = try await captureKit(FixtureCaptureSession(), into: parent.appendingPathComponent("kit"), options: options)
        #expect(result.manifest.assets.allSatisfy { $0.file == nil && $0.status == "uncached-or-oversize" })
    }
}

@Test func resourceCountLimitIsExplicit() async throws {
    try await withCaptureParent { parent in
        var options = fixtureOptions()
        options.maximumResources = 1
        let result = try await captureKit(FixtureCaptureSession(), into: parent.appendingPathComponent("kit"), options: options)
        #expect(result.manifest.assets.count == 1)
        #expect(result.manifest.warnings.contains { $0.code == "resource-limit" })
    }
}

@Test func missingResourceDoesNotDiscardKit() async throws {
    try await withCaptureParent { parent in
        let result = try await captureKit(FixtureCaptureSession(fault: .resource), into: parent.appendingPathComponent("kit"))
        #expect(result.manifest.assets.allSatisfy { $0.status == "unavailable" })
    }
}

@Test func optionalExportsCanBeDisabled() async throws {
    try await withCaptureParent { parent in
        var options = fixtureOptions()
        options.collectAssets = false
        options.collectComputedStyles = false
        options.captureSections = false
        options.fullPageMaximumPixels = 0
        let session = FixtureCaptureSession()
        let result = try await captureKit(session, into: parent.appendingPathComponent("kit"), options: options)
        #expect(result.manifest.computedStylesFile == nil)
        #expect(result.manifest.fullPage == nil)
        #expect(result.manifest.sections.isEmpty)
        #expect(result.manifest.assets.isEmpty)
        let count = await session.resourceRequests
        #expect(count == 0)
    }
}

@Test func failuresCloseSessionAndRemoveStaging() async throws {
    try await withCaptureParent { parent in
        for fault in [FixtureCaptureSession.Fault.navigation, .render] {
            let destination = parent.appendingPathComponent("kit")
            let session = FixtureCaptureSession(fault: fault)
            await #expect(throws: (any Error).self) { _ = try await captureKit(session, into: destination) }
            let closed = await session.closed
            #expect(closed)
            let remaining = try FileManager.default.contentsOfDirectory(atPath: parent.path)
            #expect(remaining.isEmpty)
        }
    }
}

@Test func cancellationClosesSessionAndRemovesStaging() async throws {
    try await withCaptureParent { parent in
        let destination = parent.appendingPathComponent("kit")
        let session = FixtureCaptureSession(fault: .cancellation)
        let task = Task { try await captureKit(session, into: destination) }
        while await session.visited.isEmpty { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        let closed = await session.closed
        #expect(closed)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        #expect(remaining.isEmpty)
    }
}

@Test func resourceCancellationIsNotPublishedAsSuccess() async throws {
    try await withCaptureParent { parent in
        let session = FixtureCaptureSession(fault: .resourceCancellation)
        await #expect(throws: CancellationError.self) {
            _ = try await captureKit(session, into: parent.appendingPathComponent("kit"))
        }
        let closed = await session.closed
        #expect(closed)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        #expect(remaining.isEmpty)
    }
}

@Test func scrollGapCannotBeReportedAsComplete() async throws {
    try await withCaptureParent { parent in
        let session = FixtureCaptureSession(fault: .gap)
        do {
            let result = try await captureKit(session, into: parent.appendingPathComponent("kit"))
            #expect(result.manifest.truncated)
            #expect(result.manifest.fullPage == nil)
        } catch is CaptureFailure {
        }
    }
}

@Test func existingDestinationRemainsUntouched() async throws {
    try await withCaptureParent { parent in
        let destination = parent.appendingPathComponent("kit")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sentinel = destination.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)
        let session = FixtureCaptureSession()
        await #expect(throws: (any Error).self) { _ = try await captureKit(session, into: destination) }
        let sentinelBytes = try Data(contentsOf: sentinel)
        #expect(sentinelBytes == Data("keep".utf8))
        let closed = await session.closed
        #expect(closed)
    }
}

@Test func concurrentCapturesPublishIndependentKits() async throws {
    try await withCaptureParent { parent in
        let engine = ConcurrentFixtureEngine()
        let coordinator = CaptureCoordinator(engine: engine, encoder: FixtureImageEncoder())
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<3 {
                group.addTask {
                    let result = try await coordinator.capture(
                        URL(string: "https://fixture.test/\(index)")!,
                        into: parent.appendingPathComponent("kit-\(index)"), options: fixtureOptions())
                    #expect(!result.manifest.truncated)
                }
            }
            try await group.waitForAll()
        }
        let sessions = await engine.sessions
        #expect(sessions.count == 3)
        for session in sessions {
            let closed = await session.closed
            #expect(closed)
        }
        let published = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        #expect(published.count == 3)
    }
}

private actor ConcurrentFixtureEngine: AetherCaptureEngine {
    var sessions: [FixtureCaptureSession] = []
    func makeCaptureSession(viewport: CaptureViewport) async throws -> any AetherCaptureSession {
        let session = FixtureCaptureSession()
        sessions.append(session)
        return session
    }
}
