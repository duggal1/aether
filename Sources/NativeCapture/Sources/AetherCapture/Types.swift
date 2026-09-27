import Foundation

/// Coordinates are document CSS pixels, not backing-store pixels.
public struct CaptureRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var bottom: Double { y + height }
    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0
    }
    public func intersects(_ other: CaptureRect) -> Bool {
        x < other.x + other.width && x + width > other.x &&
        y < other.y + other.height && bottom > other.y
    }
}

public struct CaptureViewport: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var scale: Double
    public init(width: Int = 1440, height: Int = 900, scale: Double = 1) {
        self.width = width; self.height = height; self.scale = scale
    }
}

public enum CaptureFormat: String, Codable, Sendable {
    case webp, jpeg, png
    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
}

public struct CaptureOptions: Sendable {
    public var viewport: CaptureViewport = .init()
    /// JPEG: the image format every macOS natively encodes. WebP is honoured
    /// only where the OS reports an encoder (see NativeImageEncoder).
    public var preferredFormat: CaptureFormat = .jpeg
    public var quality: Double = 0.95
    public var overlapCSSPixels: Double = 0
    public var scrollStepFraction: Double = 0.80
    public var settleMilliseconds: Int = 180
    public var maximumScrollSteps: Int = 160
    public var maximumDocumentCSSHeight: Double = 160_000
    public var maximumResources: Int = 1_200
    public var maximumAssetBytes: Int = 30_000_000
    public var maximumSingleAssetBytes: Int = 8_000_000
    /// Pixel budget for the single vertically-joined whole-page image (and
    /// for retained per-section pixels): 32M holds several native-resolution
    /// screens. Per-tile screenshots are always written regardless of this.
    public var fullPageMaximumPixels: Int = 32_000_000
    public var collectAssets: Bool = true
    public var collectComputedStyles: Bool = true
    public var captureSections: Bool = true
    public var redactSensitiveContent: Bool = true
    public init() {}

    public func validate() throws {
        guard viewport.width > 0, viewport.height > 0, viewport.width <= 8192,
              viewport.height <= 8192, viewport.scale.isFinite, viewport.scale >= 1,
              viewport.scale <= 3, quality.isFinite, (0...1).contains(quality),
              scrollStepFraction.isFinite, (0.1...1).contains(scrollStepFraction),
              overlapCSSPixels == 0,
              settleMilliseconds >= 0, settleMilliseconds <= 10_000,
              maximumScrollSteps > 0, maximumScrollSteps <= 10_000,
              maximumDocumentCSSHeight.isFinite,
              maximumDocumentCSSHeight >= Double(viewport.height),
              maximumResources >= 0, maximumAssetBytes >= 0,
              maximumSingleAssetBytes >= 0, fullPageMaximumPixels >= 0 else {
            throw CaptureFailure.invalidOptions
        }
    }
}

public enum CaptureFailure: Error, Sendable, CustomStringConvertible {
    case invalidOptions
    case navigationFailed(String)
    case invalidRaster
    case unsupportedEncoding
    case pathNotWritable(String)
    case cancelled

    public var description: String {
        switch self {
        case .invalidOptions: "Invalid capture options"
        case .navigationFailed(let message): "Navigation failed: \(message)"
        case .invalidRaster: "Renderer returned invalid RGBA pixels"
        case .unsupportedEncoding: "No supported ImageIO image destination"
        case .pathNotWritable(let path): "Cannot write capture to \(path)"
        case .cancelled: "Capture cancelled"
        }
    }
}

public struct CaptureWarning: Codable, Sendable {
    public var code: String
    public var detail: String
    public init(_ code: String, _ detail: String) { self.code = code; self.detail = detail }
}

public struct CaptureFile: Codable, Sendable {
    public var file: String
    public var format: CaptureFormat
    public var cssY: Double
    public var cssHeight: Double
    public var pixelWidth: Int
    public var pixelHeight: Int
}

public struct CaptureSection: Codable, Sendable {
    public var id: String
    public var kind: String
    public var title: String
    public var selector: String
    public var bounds: CaptureRect
    public var screenshot: String?
    public var screenshotParts: [String]
}

public struct CaptureAsset: Codable, Sendable {
    public var sourceURL: String
    public var file: String?
    public var kind: String
    public var byteCount: Int?
    public var status: String
}

public struct CaptureManifest: Codable, Sendable {
    public var schema = 1
    public var sourceURL: String
    public var finalURL: String
    public var title: String
    public var capturedAt: Date
    public var viewport: CaptureViewport
    public var documentCSSHeight: Double
    public var truncated: Bool
    public var screenshots: [CaptureFile]
    public var fullPage: String?
    public var sections: [CaptureSection]
    public var assets: [CaptureAsset]
    public var warnings: [CaptureWarning]
    public var htmlFile = "website.html"
    public var cssDirectory = "styles"
    public var computedStylesFile: String?
    public var engineName: String
}

public struct CaptureResult: Sendable {
    public var directory: URL
    public var manifest: CaptureManifest
}
