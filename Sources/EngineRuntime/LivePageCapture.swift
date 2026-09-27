import AetherCapture
import EngineCore
import Foundation

/// A full-page screenshot, and optionally the page's source, taken from the
/// page that is already open.
public struct LivePageCapture: Sendable {
  public var directory: URL
  /// The single stitched image, relative to `directory`.
  public var imageFile: String?
  public var imageFormat: String?
  public var pixelWidth: Int
  public var pixelHeight: Int
  /// Viewport tiles in document order, relative to `directory`. These are
  /// always written, even when the stitched image exceeds its pixel budget.
  public var screenshots: [String]
  /// Joined screenshots of each detected section, when sections were found.
  public var sectionFiles: [String]
  public var htmlFile: String?
  public var cssFiles: [String]
  public var computedStylesFile: String?
  public var manifestFile: String?
  public var truncated: Bool
  public var warnings: [String]
}

extension BrowserRuntime {
  /// Screenshot the live page, rather than re-opening its address.
  ///
  /// The capture pipeline in `AetherCapture` navigates a brand-new context, and
  /// a new context has no cookies — so a "screenshot this page" built on it
  /// photographs the signed-out view of a signed-in page. This walks the page
  /// that is already on screen with the same primitives that pipeline uses
  /// (`captureState`, `scrollTo`, `render`, `captureDocument`), so what is
  /// written is what the person is looking at, session and all.
  ///
  /// One descent down the page, start to finish: scrolling shakes lazy
  /// content loose, so the tiles rendered on the way down ARE the capture.
  /// Tiles are trimmed to the band of the document they actually cover, so the
  /// stitched image has no repeated band where the scroll positions overlapped.
  @discardableResult
  public func captureLivePage(
    pageID: PageID, into directory: URL, includeSource: Bool,
    options: CaptureOptions = .init()
  ) async throws -> LivePageCapture {
    try options.validate()
    var warnings: [String] = []

    let opened = try await captureState(pageID: pageID)
    guard opened.url != nil else { throw CaptureFailure.navigationFailed("Page has no URL") }
    let viewportHeight = max(1, opened.viewport.height)
    let viewportWidth = max(1, opened.viewport.width)
    let home = opened.scroll

    do {
      return try await captureLivePageDown(
        pageID: pageID, into: directory, includeSource: includeSource,
        options: options, viewportWidth: viewportWidth, viewportHeight: viewportHeight,
        home: home, sourceURL: opened.url?.absoluteString ?? "", title: opened.title,
        warnings: warnings)
    } catch {
      try? await scrollTo(pageID: pageID, x: home.x, y: home.y)
      throw error
    }
  }

  private func captureLivePageDown(
    pageID: PageID, into directory: URL, includeSource: Bool,
    options: CaptureOptions, viewportWidth: Double, viewportHeight: Double,
    home: Point, sourceURL: String, title: String, warnings parentWarnings: [String]
  ) async throws -> LivePageCapture {
    var warnings = parentWarnings
    try await scrollTo(pageID: pageID, x: 0, y: 0)
    try await Task.sleep(for: .milliseconds(options.settleMilliseconds))
    var knownHeight = (try await captureState(pageID: pageID)).documentSize.height

    var result = LivePageCapture(
      directory: directory, imageFile: nil, imageFormat: nil, pixelWidth: 0, pixelHeight: 0,
      screenshots: [], sectionFiles: [], htmlFile: nil, cssFiles: [], computedStylesFile: nil,
      manifestFile: nil, truncated: false, warnings: [])

    let limit = options.maximumDocumentCSSHeight
    if knownHeight > limit {
      result.truncated = true
      warnings.append("height-limit: page exceeded \(Int(options.maximumDocumentCSSHeight)) CSS px; capture is partial")
    }

    let encoder = NativeImageEncoder()
    let folder = directory
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

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
    var tileFiles: [String] = []
    var covered = 0.0
    let step = max(1, viewportHeight * options.scrollStepFraction)
    var lastScroll = -1.0
    var stalled = 0
    var iterations = 0

    while iterations < options.maximumScrollSteps {
      try Task.checkCancellation()
      let maxY = min(knownHeight, options.maximumDocumentCSSHeight)
      if covered >= maxY - 0.5 { break }
      let target = min(Double(iterations) * step, max(0, maxY - viewportHeight))
      try await scrollTo(pageID: pageID, x: 0, y: target)
      try await Task.sleep(for: .milliseconds(options.settleMilliseconds))
      let state = try await captureState(pageID: pageID)
      knownHeight = max(knownHeight, state.documentSize.height)
      let scrollY = state.scroll.y
      guard scrollY.isFinite, scrollY >= 0 else {
        throw CaptureFailure.navigationFailed("Page returned an invalid scroll position")
      }
      if scrollY <= lastScroll + 0.5 { stalled += 1 } else { stalled = 0 }
      if stalled >= 3 { break }
      lastScroll = scrollY
      if scrollY > covered + 0.5 { break }

      let top = max(covered, scrollY)
      let bottom = min(min(knownHeight, options.maximumDocumentCSSHeight), scrollY + state.viewport.height)
      guard bottom > top else { iterations += 1; continue }

      let rasters = try await render(pageID: pageID, origin: Point(x: 0, y: scrollY))
      guard rasters.width > 0, rasters.height > 0 else { throw CaptureFailure.invalidRaster }
      let full = try AetherRaster(
        rgba: Data(rasters.bytes), width: rasters.width, height: rasters.height,
        bytesPerRow: rasters.width * 4)
      let pixelsPerCSS = Double(full.height) / max(1, state.viewport.height)
      let dropTop = min(full.height, max(0, Int(((top - scrollY) * pixelsPerCSS).rounded())))
      let keep = min(
        full.height - dropTop,
        max(1, Int(((bottom - top) * pixelsPerCSS).rounded())))
      let trimmed = try RasterCropper.rows(full, startingAt: dropTop, count: keep)
      // Every tile is saved as it lands: whatever the OS natively encodes
      // (JPEG first — see NativeImageEncoder) is what gets written, so a
      // capture always lands images instead of an encoding error.
      let encoded = try encoder.encode(
        trimmed, preferred: options.preferredFormat, quality: options.quality)
      let name = String(format: "screenshots/%04d.%@", tileFiles.count + 1, encoded.format.fileExtension)
      try encoded.bytes.write(to: folder.appendingPathComponent(name))
      tileFiles.append(name)
      if options.fullPageMaximumPixels > 0,
         keptPixels + trimmed.width * trimmed.height <= options.fullPageMaximumPixels {
        keptTiles.append(KeptTile(cssY: top, cssHeight: bottom - top,
                                  viewportCSSWidth: state.viewport.width,
                                  pixelsPerCSSX: Double(trimmed.width) / max(1, state.viewport.width),
                                  pixelsPerCSSY: pixelsPerCSS, raster: trimmed))
        keptPixels += trimmed.width * trimmed.height
      }
      covered = bottom
      iterations += 1
    }
    result.screenshots = tileFiles

    let maxY = min(knownHeight, options.maximumDocumentCSSHeight)
    if covered < maxY - 0.5 {
      result.truncated = true
      warnings.append("incomplete-capture: scrolling stopped before the whole document was covered")
    }

    // The DOM is read AFTER the descent, so lazy content the scrolling shook
    // loose is in it: section geometry over the final document, and — for an
    // agent capture — the definitive HTML and CSS.
    try await scrollTo(pageID: pageID, x: 0, y: 0)
    let document = try await captureDocument(
      pageID: pageID, includeComputedStyles: options.collectComputedStyles && includeSource,
      redactSensitive: options.redactSensitiveContent)
    var sections = SectionDetector.detect(
      nodes: document.nodes.map {
        AetherDocumentNode(selector: $0.selector, tag: $0.tag, role: $0.role, text: $0.text,
          bounds: CaptureRect(x: $0.bounds.minX, y: $0.bounds.minY,
                              width: $0.bounds.width, height: $0.bounds.height),
          computedStyles: $0.computedStyles)
      }, documentHeight: maxY)
    if sections.isEmpty {
      sections = SectionDetector.bands(documentHeight: maxY, viewportWidth: viewportWidth,
                                       viewportHeight: viewportHeight)
    }
    // Per-section images from the retained tiles: part files per tile plus
    // one joined image per section — hero, footer, and the rest by name.
    var sectionCrops: [Int: [AetherRaster]] = [:]
    var sectionKeptPixels = 0
    for index in sections.indices where sections[index].bounds.y < covered {
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
          tile.raster, x: xStart, y: yStart, width: xEnd - xStart, height: yEnd - yStart)
        let partImage = try encoder.encode(
          crop, preferred: options.preferredFormat, quality: options.quality)
        let partFile = String(format: "sections/%@-part-%03d.%@",
          sections[index].id, sections[index].screenshotParts.count + 1,
          partImage.format.fileExtension)
        try partImage.bytes.write(to: folder.appendingPathComponent(partFile))
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
        let image = try encoder.encode(
          joined, preferred: options.preferredFormat, quality: options.quality)
        let name = "sections/\(sections[index].id).\(image.format.fileExtension)"
        try image.bytes.write(to: folder.appendingPathComponent(name))
        sections[index].screenshot = name
      }
    }
    try JSONEncoder().encode(sections).write(to: folder.appendingPathComponent("sections.json"))
    result.sectionFiles = sections.compactMap(\.screenshot)

    if let joined = keptTiles.count == tileFiles.count
      ? try FullPageAssembler.join(keptTiles.map(\.raster), maximumPixels: options.fullPageMaximumPixels) : nil,
      !result.truncated, covered >= maxY - 0.5 {
      let encoded = try encoder.encode(
        joined, preferred: options.preferredFormat, quality: options.quality)
      let name = "full-page.\(encoded.format.fileExtension)"
      try encoded.bytes.write(to: folder.appendingPathComponent(name))
      result.imageFile = name
      result.imageFormat = encoded.format.rawValue
      result.pixelWidth = joined.width
      result.pixelHeight = joined.height
    } else if !tileFiles.isEmpty, result.imageFile == nil {
      warnings.append("image-limit: the stitched image would have exceeded the configured pixel budget; per-tile screenshots still saved")
    }

    if includeSource {
      try Data(document.html.utf8).write(to: folder.appendingPathComponent("website.html"))
      result.htmlFile = "website.html"
      if !document.stylesheets.isEmpty {
        let styles = folder.appendingPathComponent("styles", isDirectory: true)
        try FileManager.default.createDirectory(at: styles, withIntermediateDirectories: true)
        for (index, sheet) in document.stylesheets.enumerated() {
          let name = String(format: "styles/%04d.css", index + 1)
          try Data(sheet.css.utf8).write(to: folder.appendingPathComponent(name))
          result.cssFiles.append(name)
        }
      }
      if options.collectComputedStyles {
        let encoded = try JSONEncoder().encode(document.nodes.map(\.computedStyles))
        try encoded.write(to: folder.appendingPathComponent("computed-styles.json"))
        result.computedStylesFile = "computed-styles.json"
      }
      for issue in document.issues { warnings.append("\(issue.code): \(issue.detail)") }
    }

    // The page is left where it was found, not at its bottom.
    try? await scrollTo(pageID: pageID, x: home.x, y: home.y)

    result.warnings = warnings
    let manifest: [String: Any] = [
      "sourceURL": sourceURL,
      "title": title,
      "capturedAt": ISO8601DateFormatter().string(from: Date()),
      "documentCSSHeight": knownHeight,
      "truncated": result.truncated,
      "image": result.imageFile ?? "",
      "imageFormat": result.imageFormat ?? "",
      "pixelWidth": result.pixelWidth,
      "pixelHeight": result.pixelHeight,
      "screenshots": tileFiles,
      "sections": sections.map { section in
        ["id": section.id, "kind": section.kind, "title": section.title,
         "screenshot": section.screenshot ?? ""] as [String: Any]
      },
      "html": result.htmlFile ?? "",
      "computedStyles": result.computedStylesFile ?? "",
      "warnings": warnings,
    ]
    if let data = try? JSONSerialization.data(
      withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
      try data.write(to: folder.appendingPathComponent("manifest.json"))
      result.manifestFile = "manifest.json"
    }
    return result
  }
}
