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
        var page = try await session.state()
        if let blocked = page.blockedReason { throw CaptureFailure.navigationFailed(blocked) }
        guard page.documentCSSHeight.isFinite, page.documentCSSHeight > 0,
              page.viewportCSSHeight.isFinite, page.viewportCSSHeight > 0 else {
            throw CaptureFailure.navigationFailed("Engine returned invalid layout dimensions")
        }
        let output = CaptureFolder(destination: destination)
        try output.prepare()
        defer { output.discard() }
        var warnings: [CaptureWarning] = []

        // First natural scroll pass: trigger IntersectionObserver content,
        // CSS animations and deferred images. Avoid hard-coded networkidle:
        // analytics and WebSockets can stay active forever.
        let discoveredHeight = try await warmLazyContent(session, options: options)
        try await session.scrollTo(documentY: 0)
        try await session.waitForVisualStability(maxMilliseconds: options.settleMilliseconds)
        page = try await session.state()
        let limit = options.maximumDocumentCSSHeight
        let measuredHeight = max(discoveredHeight, page.documentCSSHeight)
        let truncated = measuredHeight > limit
        if truncated {
            warnings.append(.init("height-limit", "Page exceeded configured document height; capture is partial"))
        }

        // Read DOM/CSSOM once after the lazy-content warm pass. This supplies
        // section geometry before screenshot tiles, enabling section crops
        // without retaining an entire document worth of uncompressed pixels.
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
            ? SectionDetector.detect(nodes: nodes, documentHeight: min(measuredHeight, limit)) : []
        let rawStep = page.viewportCSSHeight * options.scrollStepFraction
        let scrollStep = max(1, rawStep)
        var screenshots: [CaptureFile] = []
        var tilesForComposite: [AetherRaster] = []
        var keptPixels = 0
        var coveredCSSY = 0.0
        var lastScrollY = -1.0
        var noProgress = 0
        var iterations = 0
        let maxY = min(measuredHeight, limit)
        while iterations < options.maximumScrollSteps, coveredCSSY < maxY - 0.5 {
            try Task.checkCancellation()
            let targetY = min(Double(iterations) * scrollStep, max(0, maxY - page.viewportCSSHeight))
            try await session.scrollTo(documentY: targetY)
            try await session.waitForVisualStability(maxMilliseconds: options.settleMilliseconds)
            let observed = try await session.state()
            guard observed.scrollY.isFinite, observed.scrollY >= 0 else {
                throw CaptureFailure.navigationFailed("Engine returned an invalid scroll position")
            }
            if observed.scrollY <= lastScrollY + 0.5 { noProgress += 1 } else { noProgress = 0 }
            if noProgress >= 3 { break }
            lastScrollY = observed.scrollY
            if observed.scrollY > coveredCSSY + 0.5 { break }
            let visibleTop = max(coveredCSSY, observed.scrollY)
            let visibleBottom = min(maxY, observed.scrollY + observed.viewportCSSHeight)
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
            if options.captureSections {
                let tileRect = CaptureRect(x: 0, y: visibleTop,
                                           width: observed.viewportCSSWidth,
                                           height: visibleBottom - visibleTop)
                for index in sections.indices where sections[index].bounds.intersects(tileRect) {
                    let bounds = sections[index].bounds
                    let xStart = max(0, Int((bounds.x * pixelsPerCSS).rounded(.down)))
                    let xEnd = min(trimmed.width, Int(((bounds.x + bounds.width) * pixelsPerCSS).rounded(.up)))
                    let yStart = max(0, Int(((max(bounds.y, visibleTop) - visibleTop) * pixelsPerCSS).rounded(.down)))
                    let yEnd = min(trimmed.height, Int(((min(bounds.bottom, visibleBottom) - visibleTop) * pixelsPerCSS).rounded(.up)))
                    if xEnd > xStart && yEnd > yStart {
                        let sectionRaster = try RasterCropper.rectangle(
                            trimmed, x: xStart, y: yStart,
                            width: xEnd - xStart, height: yEnd - yStart
                        )
                        let sectionImage = try encoder.encode(sectionRaster,
                            preferred: options.preferredFormat, quality: options.quality)
                        let sectionFile = String(format: "sections/%@-part-%03d.%@",
                            sections[index].id, sections[index].screenshotParts.count + 1,
                            sectionImage.format.fileExtension)
                        try output.write(sectionImage.bytes, relative: sectionFile)
                        sections[index].screenshotParts.append(sectionFile)
                        if sections[index].screenshot == nil { sections[index].screenshot = sectionFile }
                    }
                }
            }
            screenshots.append(.init(file: file, format: encoded.format, cssY: visibleTop,
                                     cssHeight: visibleBottom - visibleTop,
                                     pixelWidth: trimmed.width, pixelHeight: trimmed.height))
            coveredCSSY = visibleBottom
            if options.fullPageMaximumPixels > 0 &&
                trimmed.width <= options.fullPageMaximumPixels / max(1, keptPixels / max(1, trimmed.width) + trimmed.height) {
                tilesForComposite.append(trimmed)
                keptPixels += trimmed.width * trimmed.height
            } else { tilesForComposite.removeAll(keepingCapacity: false) }
            iterations += 1
        }
        if coveredCSSY < maxY - 0.5 {
            warnings.append(.init("incomplete-capture", "Scroll stopped before covering the entire measured page"))
        }
        if screenshots.count > 1 {
            warnings.append(.init("fixed-overlays", "If repeated fixed/sticky elements appear, implement de-duplication in Aether renderer's capture mode"))
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
           tilesForComposite.count == screenshots.count,
           let composite = try FullPageAssembler.join(tilesForComposite, maximumPixels: options.fullPageMaximumPixels) {
            let encoded = try encoder.encode(composite, preferred: options.preferredFormat, quality: options.quality)
            let path = "full-page.\(encoded.format.fileExtension)"
            try output.write(encoded.bytes, relative: path)
            fullPage = path
        }
        let manifest = CaptureManifest(
            sourceURL: source.absoluteString, finalURL: page.finalURL.absoluteString,
            title: page.title, capturedAt: Date(), viewport: options.viewport,
            documentCSSHeight: measuredHeight, truncated: truncated || coveredCSSY < maxY - 0.5,
            screenshots: screenshots, fullPage: fullPage, sections: sections,
            assets: assets, warnings: warnings, computedStylesFile: computedStylesFile,
            engineName: "Aether (native capture port)"
        )
        try output.writeJSON(manifest, relative: "manifest.json")
        try output.write(Data(DesignReference.render(manifest: manifest).utf8), relative: "design-reference.md")
        try output.finish()
        return CaptureResult(directory: destination, manifest: manifest)
    }

    private func warmLazyContent(
        _ session: any AetherCaptureSession, options: CaptureOptions
    ) async throws -> Double {
        var state = try await session.state()
        var maxHeight = state.documentCSSHeight
        var priorBottom = -1.0
        var stableBottomCount = 0
        for step in 0..<options.maximumScrollSteps {
            try Task.checkCancellation()
            let nextY = min(Double(step) * state.viewportCSSHeight * options.scrollStepFraction,
                            max(0, state.documentCSSHeight - state.viewportCSSHeight))
            try await session.scrollTo(documentY: nextY)
            try await session.waitForVisualStability(maxMilliseconds: options.settleMilliseconds)
            state = try await session.state()
            maxHeight = max(maxHeight, state.documentCSSHeight)
            if state.scrollY + state.viewportCSSHeight >= state.documentCSSHeight - 1 {
                stableBottomCount = abs(priorBottom - state.documentCSSHeight) <= 1 ? stableBottomCount + 1 : 0
                priorBottom = state.documentCSSHeight
                if stableBottomCount >= 2 { break }
            }
            if state.documentCSSHeight > options.maximumDocumentCSSHeight { break }
        }
        return maxHeight
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
