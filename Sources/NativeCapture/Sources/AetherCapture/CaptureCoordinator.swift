import Foundation

/// The exported directory is the AI Kit. This actor owns no rendering engine;
/// every page operation is delegated to the supplied Aether engine session.
public actor CaptureCoordinator {
    private let engine: any AetherCaptureEngine
    private let encoder: any AetherImageEncoder
    public init(engine: any AetherCaptureEngine, encoder: any AetherImageEncoder = NativeImageEncoder()) {
        self.engine = engine; self.encoder = encoder
    }

    @discardableResult
    public func capture(
        _ rawURL: URL, into destination: URL,
        options: CaptureOptions = .init()
    ) async throws -> CaptureResult {
        try options.validate()
        guard ["http", "https"].contains(rawURL.scheme?.lowercased() ?? "") else {
            throw CaptureFailure.navigationFailed("Only HTTP(S) pages are capturable")
        }
        let session = try await engine.makeCaptureSession(viewport: options.viewport)
        do {
            let result = try await perform(rawURL, into: destination, options: options, session: session)
            await session.close()
            return result
        } catch {
            await session.close()
            throw error
        }
    }

    private func perform(
        _ source: URL, into destination: URL, options: CaptureOptions,
        session: any AetherCaptureSession
    ) async throws -> CaptureResult {
        try Task.checkCancellation()
        try await session.navigate(to: source)
        var page = try await session.state().validated()
        let output = CaptureFolder(destination: destination)
        try output.prepare()
        defer { output.discard() }
        var warnings: [CaptureWarning] = []

        // One descent down the page, start to finish. Scrolling is what shakes
        // lazy images, IntersectionObserver content and CSS animations loose,
        // so the tiles rendered on the way down ARE the capture — there is no
        // separate warm pass scrolling the page a second time. The document
        // height is re-read after every step, so content the descent itself
        // reveals extends the loop instead of being missed.
        try await session.scrollTo(documentY: 0)
        try await session.waitForVisualStability(maxMilliseconds: options.settleMilliseconds)
        page = try await session.state().validated()
        var knownHeight = page.documentCSSHeight

        let rawStep = page.viewportCSSHeight * options.scrollStepFraction
        let scrollStep = max(1, rawStep)
        var screenshots: [CaptureFile] = []
        // Tiles kept for the whole-page composite and the per-section images.
        // Retention is gated by the pixel budget; the tile FILES are always
        // written, so an over-budget page still lands every image.
        struct KeptTile {
            var cssY: Double
            var cssHeight: Double
            var viewportCSSWidth: Double
            var pixelsPerCSSX: Double
            var pixelsPerCSSY: Double
            var raster: AetherRaster
        }
        var keptTiles: [KeptTile] = []
        var keptPixels = 0
        var coveredCSSY = 0.0
        var lastScrollY = -1.0
        var noProgress = 0
        var iterations = 0
        while iterations < options.maximumScrollSteps {
            try Task.checkCancellation()
            let maxY = min(knownHeight, options.maximumDocumentCSSHeight)
            if coveredCSSY >= maxY - 0.5 { break }
            let targetY = min(Double(iterations) * scrollStep, max(0, maxY - page.viewportCSSHeight))
            try await session.scrollTo(documentY: targetY)
            try await session.waitForVisualStability(maxMilliseconds: options.settleMilliseconds)
            let observed = try await session.state().validated()
            knownHeight = max(knownHeight, observed.documentCSSHeight)
            guard observed.scrollY.isFinite, observed.scrollY >= 0 else {
                throw CaptureFailure.navigationFailed("Engine returned an invalid scroll position")
            }
            if observed.scrollY <= lastScrollY + 0.5 { noProgress += 1 } else { noProgress = 0 }
            if noProgress >= 3 { break }
            lastScrollY = observed.scrollY
            if observed.scrollY > coveredCSSY + 0.5 { break }
            let visibleTop = max(coveredCSSY, observed.scrollY)
            let visibleBottom = min(min(knownHeight, options.maximumDocumentCSSHeight),
                                    observed.scrollY + observed.viewportCSSHeight)
            guard visibleBottom > visibleTop else { iterations += 1; continue }
            let nativeRaster = try await session.renderViewport()
            let pixelsPerCSS = Double(nativeRaster.height) / observed.viewportCSSHeight
            let removeTop = min(nativeRaster.height, max(0, Int(((visibleTop - observed.scrollY) * pixelsPerCSS).rounded())))
            let needed = min(nativeRaster.height - removeTop,
                             max(1, Int(((visibleBottom - visibleTop) * pixelsPerCSS).rounded())))
            let trimmed = try RasterCropper.rows(nativeRaster, startingAt: removeTop, count: needed)
            let encoded = try encoder.encode(trimmed, preferred: options.preferredFormat, quality: options.quality)
            let file = String(format: "screenshots/%04d.%@", screenshots.count + 1, encoded.format.fileExtension)
            try output.write(encoded.bytes, relative: file)
            screenshots.append(.init(file: file, format: encoded.format, cssY: visibleTop,
                                     cssHeight: visibleBottom - visibleTop,
                                     pixelWidth: trimmed.width, pixelHeight: trimmed.height))
            if options.fullPageMaximumPixels > 0,
               keptPixels + trimmed.width * trimmed.height <= options.fullPageMaximumPixels {
                keptTiles.append(KeptTile(cssY: visibleTop, cssHeight: visibleBottom - visibleTop,
                                          viewportCSSWidth: observed.viewportCSSWidth,
                                          pixelsPerCSSX: Double(trimmed.width) / observed.viewportCSSWidth,
                                          pixelsPerCSSY: pixelsPerCSS, raster: trimmed))
                keptPixels += trimmed.width * trimmed.height
            }
            coveredCSSY = visibleBottom
            iterations += 1
        }
        let maxY = min(knownHeight, options.maximumDocumentCSSHeight)
        var truncated = false
        if knownHeight > options.maximumDocumentCSSHeight {
            truncated = true
            warnings.append(.init("height-limit", "Page exceeded configured document height; capture is partial"))
        }
        if coveredCSSY < maxY - 0.5 {
            truncated = true
            warnings.append(.init("incomplete-capture", "Scroll stopped before covering the entire measured page"))
        }
        if screenshots.count > 1 {
            warnings.append(.init("fixed-overlays", "If repeated fixed/sticky elements appear, implement de-duplication in Aether renderer's capture mode"))
        }
        page = try await session.state().validated()

        // The DOM is read AFTER the descent, so lazy content the scrolling
        // shook loose is in it: the definitive HTML, CSSOM, section geometry
        // and resource list. Read back at the top, where the coordinates the
        // tiles were trimmed in still hold.
        try await session.scrollTo(documentY: 0)
        let snapshot = try await session.snapshot(
            includeComputedStyles: options.collectComputedStyles,
            redactSensitive: options.redactSensitiveContent
        )
        warnings += snapshot.warnings
        try output.write(Data(snapshot.html.utf8), relative: "website.html")
        var cssManifest: [[String: String]] = []
        for (index, stylesheet) in snapshot.stylesheets.enumerated() {
            let path = String(format: "styles/%04d.css", index + 1)
            try output.write(Data(stylesheet.css.utf8), relative: path)
            cssManifest.append([
                "file": path, "sourceURL": stylesheet.sourceURL ?? "inline",
                "media": stylesheet.media ?? "all"
            ])
        }
        try output.writeJSON(cssManifest, relative: "styles/index.json")
        let nodes = snapshot.nodes
        var computedStylesFile: String? = nil
        if options.collectComputedStyles {
            computedStylesFile = "computed-styles.json"
            try output.writeJSON(nodes, relative: computedStylesFile!)
        }
        var sections = options.captureSections
            ? SectionDetector.detect(nodes: nodes, documentHeight: maxY) : []
        if options.captureSections, sections.isEmpty {
            sections = SectionDetector.bands(documentHeight: maxY, viewportWidth: page.viewportCSSWidth,
                                             viewportHeight: page.viewportCSSHeight)
        }
        // Per-section images, cropped from the retained tiles: part files per
        // tile plus one joined image per section — hero, footer, and the rest
        // by their clean names.
        if options.captureSections {
            var sectionCrops: [Int: [AetherRaster]] = [:]
            var sectionKeptPixels = 0
            for index in sections.indices {
                let bounds = sections[index].bounds
                for tile in keptTiles {
                    let tileBottom = tile.cssY + tile.cssHeight
                    let top = max(bounds.y, tile.cssY)
                    let bottom = min(bounds.bottom, tileBottom)
                    guard bottom > top else { continue }
                    let xStart = Int((min(tile.viewportCSSWidth, max(0, bounds.x)) * tile.pixelsPerCSSX).rounded(.down))
                    let xEnd = Int((min(tile.viewportCSSWidth, max(0, bounds.x + bounds.width)) * tile.pixelsPerCSSX).rounded(.up))
                    let yStart = max(0, Int(((top - tile.cssY) * tile.pixelsPerCSSY).rounded(.down)))
                    let yEnd = min(tile.raster.height, Int(((bottom - tile.cssY) * tile.pixelsPerCSSY).rounded(.up)))
                    guard xEnd > xStart, yEnd > yStart else { continue }
                    let crop = try RasterCropper.rectangle(
                        tile.raster, x: xStart, y: yStart,
                        width: xEnd - xStart, height: yEnd - yStart
                    )
                    let partImage = try encoder.encode(crop,
                        preferred: options.preferredFormat, quality: options.quality)
                    let partFile = String(format: "sections/%@-part-%03d.%@",
                        sections[index].id, sections[index].screenshotParts.count + 1,
                        partImage.format.fileExtension)
                    try output.write(partImage.bytes, relative: partFile)
                    sections[index].screenshotParts.append(partFile)
                    if sections[index].screenshot == nil { sections[index].screenshot = partFile }
                    if options.fullPageMaximumPixels > 0,
                       sectionKeptPixels + crop.width * crop.height <= options.fullPageMaximumPixels {
                        sectionCrops[index, default: []].append(crop)
                        sectionKeptPixels += crop.width * crop.height
                    }
                }
                if let crops = sectionCrops[index], crops.count > 1,
                   let joined = try? FullPageAssembler.join(crops, maximumPixels: options.fullPageMaximumPixels) {
                    let image = try encoder.encode(joined,
                        preferred: options.preferredFormat, quality: options.quality)
                    let name = "sections/\(sections[index].id).\(image.format.fileExtension)"
                    try output.write(image.bytes, relative: name)
                    sections[index].screenshot = name
                }
            }
        }
        for index in sections.indices {
            if sections[index].bounds.y >= coveredCSSY {
                sections[index].screenshot = nil
                sections[index].screenshotParts = []
            }
        }
        try output.writeJSON(sections, relative: "sections.json")
        var assets: [CaptureAsset] = []
        if options.collectAssets {
            let refs = ResourceCollector.candidates(snapshot: snapshot, baseURL: page.finalURL)
            if refs.count > options.maximumResources {
                warnings.append(.init("resource-limit", "Some resources omitted due to configured limit"))
            }
            var total = 0
            for ref in refs.prefix(options.maximumResources) {
                try Task.checkCancellation()
                guard let url = URL(string: ref.url) else { continue }
                let file = ResourceCollector.safeRelativePath(for: url, kind: ref.kind)
                if total >= options.maximumAssetBytes {
                    assets.append(.init(sourceURL: ref.url, file: nil, kind: ref.kind,
                                        byteCount: nil, status: "total-byte-budget"))
                    continue
                }
                do {
                    let cap = min(options.maximumSingleAssetBytes, options.maximumAssetBytes - total)
                    if let bytes = try await session.resourceBytes(for: url, maximumBytes: cap),
                       bytes.count <= cap {
                        try output.write(bytes, relative: file)
                        total += bytes.count
                        assets.append(.init(sourceURL: ref.url, file: file, kind: ref.kind,
                                            byteCount: bytes.count, status: "saved"))
                    } else {
                        assets.append(.init(sourceURL: ref.url, file: nil, kind: ref.kind,
                                            byteCount: nil, status: "uncached-or-oversize"))
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try Task.checkCancellation()
                    assets.append(.init(sourceURL: ref.url, file: nil, kind: ref.kind,
                                        byteCount: nil, status: "unavailable"))
                }
            }
        }
        var fullPage: String? = nil
        if !truncated, coveredCSSY >= maxY - 0.5,
           keptTiles.count == screenshots.count,
           let composite = try FullPageAssembler.join(keptTiles.map(\.raster), maximumPixels: options.fullPageMaximumPixels) {
            let encoded = try encoder.encode(composite, preferred: options.preferredFormat, quality: options.quality)
            let path = "full-page.\(encoded.format.fileExtension)"
            try output.write(encoded.bytes, relative: path)
            fullPage = path
        }
        let manifest = CaptureManifest(
            sourceURL: source.absoluteString, finalURL: page.finalURL.absoluteString,
            title: page.title, capturedAt: Date(), viewport: options.viewport,
            documentCSSHeight: knownHeight, truncated: truncated || coveredCSSY < maxY - 0.5,
            screenshots: screenshots, fullPage: fullPage, sections: sections,
            assets: assets, warnings: warnings, computedStylesFile: computedStylesFile,
            engineName: "Aether (native capture port)"
        )
        try output.writeJSON(manifest, relative: "manifest.json")
        try output.write(Data(DesignReference.render(manifest: manifest).utf8), relative: "design-reference.md")
        try Task.checkCancellation()
        try output.finish()
        return CaptureResult(directory: destination, manifest: manifest)
    }
}

public enum RasterCropper {
    public static func rows(_ image: AetherRaster, startingAt start: Int, count: Int) throws -> AetherRaster {
        guard start >= 0, count > 0, start <= image.height - count else { throw CaptureFailure.invalidRaster }
        let startByte = start * image.bytesPerRow
        let endByte = (start + count) * image.bytesPerRow
        return try AetherRaster(rgba: image.rgba.subdata(in: startByte..<endByte),
                                width: image.width, height: count, bytesPerRow: image.bytesPerRow)
    }
}

public extension RasterCropper {
    static func rectangle(_ image: AetherRaster, x: Int, y: Int, width: Int, height: Int) throws -> AetherRaster {
        guard x >= 0, y >= 0, width > 0, height > 0,
              x <= image.width - width, y <= image.height - height else {
            throw CaptureFailure.invalidRaster
        }
        let bytesPerRow = width * 4
        var output = Data(count: height * bytesPerRow)
        output.withUnsafeMutableBytes { destination in
            image.rgba.withUnsafeBytes { source in
                guard let dst = destination.baseAddress, let src = source.baseAddress else { return }
                for row in 0..<height {
                    memcpy(dst.advanced(by: row * bytesPerRow),
                           src.advanced(by: (row + y) * image.bytesPerRow + x * 4), bytesPerRow)
                }
            }
        }
        return try AetherRaster(rgba: output, width: width, height: height, bytesPerRow: bytesPerRow)
    }
}
