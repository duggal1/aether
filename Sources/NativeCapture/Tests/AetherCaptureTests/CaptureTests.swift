import Foundation
import Testing
@testable import AetherCapture

private struct TestEncoder: AetherImageEncoder {
    func encode(_ raster: AetherRaster, preferred: CaptureFormat, quality: Double) throws -> EncodedImage {
        #expect(raster.rgba.count == raster.bytesPerRow * raster.height)
        return .init(bytes: Data("\(raster.width)x\(raster.height)".utf8), format: preferred == .png ? .png : .jpeg)
    }
}

private struct TestEngine: AetherCaptureEngine {
    let session: TestSession
    func makeCaptureSession(viewport: CaptureViewport) async throws -> any AetherCaptureSession { session }
}

private actor TestSession: AetherCaptureSession {
    let url = URL(string: "https://example.com/after-redirect")!
    let viewportHeight: Double = 80
    var y: Double = 0
    var closed = false
    func navigate(to url: URL) async throws {}
    func scrollTo(documentY: Double) async throws { y = min(max(0, documentY), 160) }
    func waitForVisualStability(maxMilliseconds: Int) async throws {}
    func state() async throws -> AetherPageState {
        .init(finalURL: url, title: "Demo", viewportCSSWidth: 100,
              viewportCSSHeight: viewportHeight, documentCSSHeight: 240, scrollY: y)
    }
    func renderViewport() async throws -> AetherRaster {
        try AetherRaster(rgba: Data(repeating: UInt8(y), count: 100 * 80 * 4),
                         width: 100, height: 80, bytesPerRow: 400)
    }
    func snapshot(includeComputedStyles: Bool, redactSensitive: Bool) async throws -> AetherDocumentSnapshot {
        .init(html: "<!DOCTYPE html><html><body>Live content</body></html>",
              stylesheets: [.init(sourceURL: "https://example.com/main.css", media: "all",
                                  css: "body{background:url('/img/a.svg')}")],
              nodes: [
                .init(selector: "header", tag: "header", text: "Hero",
                      bounds: .init(x: 0, y: 0, width: 100, height: 80)),
                .init(selector: "section", tag: "section", text: "Feature",
                      bounds: .init(x: 0, y: 80, width: 100, height: 80))
              ], resources: [
                .init(url: "/img/a.svg", kind: "svg"),
                .init(url: "https://example.com/main.css", kind: "css")
              ])
    }
    func resourceBytes(for url: URL, maximumBytes: Int) async throws -> Data? {
        Data("sample-resource".utf8)
    }
    func close() async { closed = true }
}

@Test func nativeFlowExportsLivePageAndFallbackFormat() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = TestSession()
    let coordinator = CaptureCoordinator(engine: TestEngine(session: session), encoder: TestEncoder())
    var options = CaptureOptions()
    options.viewport = .init(width: 100, height: 80, scale: 1)
    options.settleMilliseconds = 0
    let result = try await coordinator.capture(URL(string: "https://example.com")!, into: root, options: options)
    #expect(result.manifest.finalURL == "https://example.com/after-redirect")
    #expect(result.manifest.screenshots.count == 4)
    #expect(result.manifest.screenshots.allSatisfy { $0.format == .jpeg && $0.file.hasSuffix(".jpg") })
    #expect(result.manifest.fullPage == "full-page.jpg")
    #expect(result.manifest.sections.count == 2)
    #expect(result.manifest.sections.allSatisfy { !$0.screenshotParts.isEmpty })
    #expect(result.manifest.sections.allSatisfy { $0.screenshotParts.allSatisfy { $0.hasSuffix(".jpg") } })
    #expect(result.manifest.assets.count == 2)
    #expect(result.manifest.assets.allSatisfy { $0.status == "saved" })
    #expect(try String(contentsOf: root.appendingPathComponent("website.html"), encoding: .utf8).contains("Live content"))
    #expect(await session.closed)
}

@Test func CSSScannerSkipsCommentsStringsAndDataURLs() {
    let css = """
    /* url(ignore.png) */
    a:before{content:"url(fake.svg)"}
    .a{background:url('/img/real.svg')}
    .b{background:url(data:image/svg+xml;base64,AAAA)}
    .c{background:url(https://example.com/test.webp)}
    """
    #expect(CSSURLScanner.references(in: css) == ["/img/real.svg", "https://example.com/test.webp"])
}

@Test func RasterCropIsByteExact() throws {
    let bytes = Data([1,2,3,4, 5,6,7,8, 9,10,11,12])
    let raster = try AetherRaster(rgba: bytes, width: 1, height: 3, bytesPerRow: 4)
    let cropped = try RasterCropper.rows(raster, startingAt: 1, count: 2)
    #expect(cropped.rgba == Data([5,6,7,8, 9,10,11,12]))
    let joined = try FullPageAssembler.join([cropped, cropped], maximumPixels: 4)
    #expect(joined?.height == 4)
    #expect(joined?.rgba == Data([5,6,7,8, 9,10,11,12, 5,6,7,8, 9,10,11,12]))
}

@Test func URLPathsStayInsideKit() {
    let url = URL(string: "https://example.com/../../danger.svg?x=y")!
    let path = ResourceCollector.safeRelativePath(for: url, kind: "svg")
    #expect(path.hasPrefix("assets/svg/"))
    #expect(!path.contains(".."))
}

@Test func RectangleCropIsByteExact() throws {
    // Two RGBA pixels per row, two rows.
    let bytes = Data(Array(0..<16).map(UInt8.init))
    let image = try AetherRaster(rgba: bytes, width: 2, height: 2, bytesPerRow: 8)
    let crop = try RasterCropper.rectangle(image, x: 1, y: 0, width: 1, height: 2)
    #expect(crop.rgba == Data([4,5,6,7, 12,13,14,15]))
}

@Test func CSSAssetURLsUseStylesheetBaseNotDocumentBase() {
    let page = URL(string: "https://example.com/a/page")!
    let snapshot = AetherDocumentSnapshot(html: "", stylesheets: [
        .init(sourceURL: "https://cdn.example.com/css/main.css", media: nil,
              css: "body{background:url('../img/icon.svg')}")
    ], nodes: [], resources: [])
    let urls = ResourceCollector.candidates(snapshot: snapshot, baseURL: page).map(\.url)
    #expect(urls.contains("https://cdn.example.com/img/icon.svg"))
}
