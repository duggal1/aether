import Foundation
@testable import AetherCapture

struct FixtureCaptureEngine: AetherCaptureEngine {
    let session: FixtureCaptureSession
    func makeCaptureSession(viewport: CaptureViewport) async throws -> any AetherCaptureSession { session }
}

actor FixtureCaptureSession: AetherCaptureSession {
    enum Fault: Sendable { case none, navigation, render, resource, resourceCancellation, cancellation, stalled, invalidGeometry, gap }
    let fault: Fault
    let grows: Bool
    var height: Double
    var y = 0.0
    var closed = false
    var navigated = false
    var visited: [Double] = []
    var resourceRequests = 0
    var snapshotY: Double?
    var snapshotHeight: Double?
    init(height: Double = 240, grows: Bool = false, fault: Fault = .none) {
        self.height = height
        self.grows = grows
        self.fault = fault
    }
    func navigate(to url: URL) async throws {
        navigated = true
        if fault == .navigation { throw CaptureFailure.navigationFailed("fixture") }
    }
    func state() async throws -> AetherPageState {
        .init(finalURL: URL(string: "https://fixture.test/final")!, title: "Fixture",
              viewportCSSWidth: 100, viewportCSSHeight: fault == .invalidGeometry && !visited.isEmpty ? .nan : 80,
              documentCSSHeight: height, scrollY: y)
    }
    func scrollTo(documentY: Double) async throws {
        y = fault == .stalled ? 0 : min(max(0, documentY), height - 80)
        if fault == .gap && y > 0 { y = min(y + 80, height - 80) }
        visited.append(y)
        if grows && y >= height - 80 && height < 400 { height += 80 }
    }
    func waitForVisualStability(maxMilliseconds: Int) async throws {
        if fault == .cancellation { try await Task.sleep(for: .seconds(30)) }
    }
    func renderViewport() async throws -> AetherRaster {
        if fault == .render { throw CaptureFailure.invalidRaster }
        var bytes = Data(count: 100 * 80 * 4)
        for row in 0..<80 {
            for column in 0..<100 {
                let index = (row * 100 + column) * 4
                bytes[index] = UInt8((Int(y) + row) % 256)
                bytes[index + 1] = UInt8(column)
                bytes[index + 3] = 255
            }
        }
        return try AetherRaster(rgba: bytes, width: 100, height: 80, bytesPerRow: 400)
    }
    func snapshot(includeComputedStyles: Bool, redactSensitive: Bool) async throws -> AetherDocumentSnapshot {
        snapshotY = y
        snapshotHeight = height
        return .init(html: "<html><body><svg viewBox=\"0 0 1 1\"><path d=\"M0 0L1 1\"/></svg>live</body></html>",
                     stylesheets: [.init(sourceURL: nil, media: "screen", css: "body{color:red}")],
                     nodes: [.init(selector: "section", tag: "section", text: "Section", bounds: .init(x: 10, y: 40, width: 80, height: 120), computedStyles: includeComputedStyles ? ["color": "red"] : [:])],
                     resources: [.init(url: "/a.svg", kind: "svg"), .init(url: "/font.woff2", kind: "font"), .init(url: "/missing.png", kind: "image")])
    }
    func resourceBytes(for url: URL, maximumBytes: Int) async throws -> Data? {
        resourceRequests += 1
        if fault == .resource { throw CaptureFailure.navigationFailed("unavailable") }
        if fault == .resourceCancellation { throw CancellationError() }
        if url.path == "/missing.png" { return nil }
        return Data(repeating: 42, count: 8)
    }
    func close() async { closed = true }
}

struct FixtureImageEncoder: AetherImageEncoder {
    func encode(_ raster: AetherRaster, preferred: CaptureFormat, quality: Double) throws -> EncodedImage {
        .init(bytes: raster.rgba, format: preferred == .png ? .png : .jpeg)
    }
}

func fixtureOptions() -> CaptureOptions {
    var options = CaptureOptions()
    options.viewport = .init(width: 100, height: 80, scale: 1)
    options.settleMilliseconds = 0
    return options
}
