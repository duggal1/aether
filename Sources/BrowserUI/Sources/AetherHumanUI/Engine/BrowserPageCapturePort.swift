import Foundation

/// A full-page capture of the page that is already open.
public struct BrowserLiveCapture: Sendable {
    public let directory: String
    public let imageFile: String?
    public let imageFormat: String?
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let htmlFile: String?
    public let computedStylesFile: String?
    public let manifestFile: String?
    public let truncated: Bool
    public let warnings: [String]

    public init(directory: String, imageFile: String?, imageFormat: String?, pixelWidth: Int,
                pixelHeight: Int, htmlFile: String?, computedStylesFile: String?,
                manifestFile: String?, truncated: Bool, warnings: [String]) {
        self.directory = directory
        self.imageFile = imageFile
        self.imageFormat = imageFormat
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.htmlFile = htmlFile
        self.computedStylesFile = computedStylesFile
        self.manifestFile = manifestFile
        self.truncated = truncated
        self.warnings = warnings
    }
}

/// A page's own source, as a bundle a person or an agent can read.
public struct BrowserPageSource: Sendable {
    public let url: String
    public let title: String
    public let html: String
    public let stylesheets: [String]
    public let computedStyles: [[String: String]]

    public init(url: String, title: String, html: String, stylesheets: [String],
                computedStyles: [[String: String]]) {
        self.url = url
        self.title = title
        self.html = html
        self.stylesheets = stylesheets
        self.computedStyles = computedStyles
    }
}

/// Taking a picture of the page in front of you, and reading its source.
///
/// Separate from `BrowserPageCapturing`-style read ports because both of these
/// act on the live page: a capture that re-navigates the address lands on the
/// signed-out copy of a signed-in page, which is not a screenshot of what the
/// person is looking at.
@MainActor
public protocol BrowserPageCapturing: AnyObject {
    /// `includeSource` also writes the HTML, CSS and computed styles beside the
    /// image — the bundle an agent reads.
    func captureLivePage(pageID: String, into directory: String, includeSource: Bool) async throws
        -> BrowserLiveCapture
    func pageSource(pageID: String) async throws -> BrowserPageSource
}
