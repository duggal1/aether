import Foundation

public struct CaptureAsset: Codable, Sendable, Equatable {
    public let originalURL: String
    public let localPath: String?
    public let status: String
    public let sha256: String?
}

public struct CaptureSection: Codable, Sendable, Equatable {
    public let index: Int
    public let scrollY: Int
    public let screenshotPath: String
    public let contentRect: CaptureRect
}

public struct DesignCaptureManifest: Codable, Sendable, Equatable {
    public let sourceURL: String
    public let capturedAt: Date
    public let viewport: CaptureViewport
    public let documentHeight: Int
    public let sections: [CaptureSection]
    public let assets: [CaptureAsset]
    public let warnings: [String]
    public let htmlPath: String?
    public let stylesheetPaths: [String]

    public init(sourceURL: String, capturedAt: Date = Date(), viewport: CaptureViewport, documentHeight: Int, sections: [CaptureSection], assets: [CaptureAsset], warnings: [String], htmlPath: String?, stylesheetPaths: [String]) {
        self.sourceURL = sourceURL
        self.capturedAt = capturedAt
        self.viewport = viewport
        self.documentHeight = documentHeight
        self.sections = sections
        self.assets = assets
        self.warnings = warnings
        self.htmlPath = htmlPath
        self.stylesheetPaths = stylesheetPaths
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
