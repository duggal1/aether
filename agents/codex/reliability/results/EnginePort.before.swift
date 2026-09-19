import Foundation

/// Implement with Aether's OWN document, renderer, layout, and resource stores.
/// No WebKit, Chromium, JavaScript injection, HTTP re-fetch, or second browser.
public protocol AetherCaptureEngine: Sendable {
    func makeCaptureSession(viewport: CaptureViewport) async throws -> any AetherCaptureSession
}

/// An isolated page, never the human user's active tab. Implementations must
/// serialize DOM mutations and renderer readbacks on the engine's page queue.
public protocol AetherCaptureSession: Sendable {
    func navigate(to url: URL) async throws
    func state() async throws -> AetherPageState
    func scrollTo(documentY: Double) async throws
    func waitForVisualStability(maxMilliseconds: Int) async throws
    /// Render the current viewport, with y = actual document scroll position.
    /// Screenshots must not hide elements or alter the document to achieve tiling.
    func renderViewport() async throws -> AetherRaster
    /// DOM and CSSOM are captured AFTER natural scrolling has loaded content.
    func snapshot(includeComputedStyles: Bool, redactSensitive: Bool) async throws -> AetherDocumentSnapshot
    /// Bytes from the existing page resource cache, never a new unauthenticated HTTP fetch.
    func resourceBytes(for url: URL, maximumBytes: Int) async throws -> Data?
    func close() async
}

public struct AetherPageState: Sendable {
    public var finalURL: URL
    public var title: String
    public var viewportCSSWidth: Double
    public var viewportCSSHeight: Double
    public var documentCSSHeight: Double
    public var scrollY: Double
    public var blockedReason: String?
    public init(finalURL: URL, title: String, viewportCSSWidth: Double,
                viewportCSSHeight: Double, documentCSSHeight: Double,
                scrollY: Double, blockedReason: String? = nil) {
        self.finalURL = finalURL; self.title = title
        self.viewportCSSWidth = viewportCSSWidth; self.viewportCSSHeight = viewportCSSHeight
        self.documentCSSHeight = documentCSSHeight; self.scrollY = scrollY
        self.blockedReason = blockedReason
    }
}

/// Row-major 8-bit RGBA, 4 channels, unpremultiplied, sRGB.
/// Keep tile readbacks bounded. Metal clients should use a staging buffer,
/// not retain full-page GPU textures or render the entire page at once.
public struct AetherRaster: Sendable {
    public let rgba: Data
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public init(rgba: Data, width: Int, height: Int, bytesPerRow: Int) throws {
        guard width > 0, height > 0, bytesPerRow >= width * 4,
              height <= Int.max / bytesPerRow,
              rgba.count == height * bytesPerRow else { throw CaptureFailure.invalidRaster }
        self.rgba = rgba; self.width = width; self.height = height; self.bytesPerRow = bytesPerRow
    }
}

public struct AetherDocumentNode: Codable, Sendable {
    public var selector: String
    public var tag: String
    public var role: String?
    public var text: String?
    public var bounds: CaptureRect
    public var computedStyles: [String: String]
    public init(selector: String, tag: String, role: String? = nil, text: String? = nil,
                bounds: CaptureRect, computedStyles: [String: String] = [:]) {
        self.selector = selector; self.tag = tag; self.role = role
        self.text = text; self.bounds = bounds; self.computedStyles = computedStyles
    }
}

public struct AetherStylesheet: Codable, Sendable {
    public var sourceURL: String?
    public var media: String?
    /// Actual loaded CSSOM text, or exact cached source, not synthesized styles.
    public var css: String
    public init(sourceURL: String?, media: String?, css: String) {
        self.sourceURL = sourceURL; self.media = media; self.css = css
    }
}

public struct AetherResourceReference: Codable, Sendable {
    public var url: String
    public var kind: String
    public init(url: String, kind: String) { self.url = url; self.kind = kind }
}

public struct AetherDocumentSnapshot: Sendable {
    public var html: String
    public var stylesheets: [AetherStylesheet]
    public var nodes: [AetherDocumentNode]
    public var resources: [AetherResourceReference]
    public var warnings: [CaptureWarning]
    public init(html: String, stylesheets: [AetherStylesheet],
                nodes: [AetherDocumentNode], resources: [AetherResourceReference],
                warnings: [CaptureWarning] = []) {
        self.html = html; self.stylesheets = stylesheets
        self.nodes = nodes; self.resources = resources; self.warnings = warnings
    }
}
