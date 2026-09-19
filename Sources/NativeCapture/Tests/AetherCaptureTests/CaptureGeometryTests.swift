import Foundation
import Testing
@testable import AetherCapture

@Test func invalidRasterDimensionsThrow() {
    for (width, height, stride) in [(0, 1, 4), (1, 0, 4), (2, 1, 4), (1, 1, -1), (1, Int.max, 4)] {
        #expect(throws: (any Error).self) {
            try AetherRaster(rgba: Data(), width: width, height: height, bytesPerRow: stride)
        }
    }
}

@Test func cropBoundsAndCompositeBudget() throws {
    let raster = try AetherRaster(rgba: Data([1, 2, 3, 4, 9, 9, 9, 9, 5, 6, 7, 8, 9, 9, 9, 9]), width: 1, height: 2, bytesPerRow: 8)
    #expect(throws: (any Error).self) { try RasterCropper.rows(raster, startingAt: -1, count: 1) }
    #expect(throws: (any Error).self) { try RasterCropper.rows(raster, startingAt: 1, count: 2) }
    #expect(throws: (any Error).self) { try RasterCropper.rectangle(raster, x: 1, y: 0, width: 1, height: 1) }
    let tooManyRows = try FullPageAssembler.join([raster, raster], maximumPixels: 3)
    #expect(tooManyRows == nil)
    let emptyJoin = try FullPageAssembler.join([], maximumPixels: 100)
    #expect(emptyJoin == nil)
    let joinedValue = try FullPageAssembler.join([raster, raster], maximumPixels: 4)
    let joined = try #require(joinedValue)
    #expect(joined.bytesPerRow == 4)
    #expect(joined.rgba == Data([1, 2, 3, 4, 5, 6, 7, 8, 1, 2, 3, 4, 5, 6, 7, 8]))
}

@Test func optionsRejectInvalidLimits() {
    var cases: [CaptureOptions] = []
    var options = CaptureOptions(); options.viewport.width = 0; cases.append(options)
    options = CaptureOptions(); options.quality = .nan; cases.append(options)
    options = CaptureOptions(); options.scrollStepFraction = 0; cases.append(options)
    options = CaptureOptions(); options.maximumScrollSteps = 0; cases.append(options)
    options = CaptureOptions(); options.fullPageMaximumPixels = -1; cases.append(options)
    options = CaptureOptions(); options.maximumDocumentCSSHeight = .infinity; cases.append(options)
    for invalid in cases { #expect(throws: (any Error).self) { try invalid.validate() } }
}

@Test func sectionsKeepSideBySideRegions() {
    let nodes = [
        AetherDocumentNode(selector: "#left", tag: "section", bounds: .init(x: 0, y: 0, width: 50, height: 80)),
        AetherDocumentNode(selector: "#right", tag: "section", bounds: .init(x: 50, y: 0, width: 50, height: 80))
    ]
    #expect(SectionDetector.detect(nodes: nodes, documentHeight: 80).count == 2)
}

@Test func relativeStylesheetAndFontURLsResolveCorrectly() {
    let snapshot = AetherDocumentSnapshot(html: "", stylesheets: [.init(sourceURL: "/css/main.css", media: nil, css: "@font-face{src:url('../fonts/a.woff2')}a{background:url('../images/a.svg')}")], nodes: [], resources: [])
    let refs = ResourceCollector.candidates(snapshot: snapshot, baseURL: URL(string: "https://fixture.test/docs/page")!)
    #expect(refs.contains { $0.url == "https://fixture.test/fonts/a.woff2" && $0.kind == "font" })
    #expect(refs.contains { $0.url == "https://fixture.test/images/a.svg" && $0.kind == "svg" })
}

@Test func rasterWidthOverflowIsRejected() {
    #expect(throws: CaptureFailure.self) {
        try AetherRaster(rgba: Data(), width: Int.max, height: 1, bytesPerRow: 4)
    }
}
