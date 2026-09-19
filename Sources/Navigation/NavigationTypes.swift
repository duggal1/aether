import CSS
import DOM
import Diagnostics
import Display
import EngineCore
import Foundation
import Images
import Layout
import Style

public struct LoadedPage: Sendable {
  public var navigationID: NavigationID
  public var url: URL
  public var statusCode: Int
  public var title: String
  public var document: DOMDocument
  public var styledDocument: StyledDocument
  public var layout: LayoutTree
  public var displayList: DisplayList
  public var metrics: EngineMetrics
  public var stylesheets: [Stylesheet]
  public var images: [NodeID: DecodedImage]
  public var scripts: [String]
  public var scriptErrors: [String]
  public var imageErrors: [String]

  public init(
    navigationID: NavigationID,
    url: URL,
    statusCode: Int,
    title: String,
    document: DOMDocument,
    styledDocument: StyledDocument,
    layout: LayoutTree,
    displayList: DisplayList,
    metrics: EngineMetrics,
    stylesheets: [Stylesheet] = [],
    images: [NodeID: DecodedImage] = [:],
    scripts: [String] = [],
    scriptErrors: [String] = [],
    imageErrors: [String] = []
  ) {
    self.navigationID = navigationID
    self.url = url
    self.statusCode = statusCode
    self.title = title
    self.document = document
    self.styledDocument = styledDocument
    self.layout = layout
    self.displayList = displayList
    self.metrics = metrics
    self.stylesheets = stylesheets
    self.images = images
    self.scripts = scripts
    self.scriptErrors = scriptErrors
    self.imageErrors = imageErrors
  }
}

public enum NavigationError: Error, Sendable, CustomStringConvertible {
  case invalidURL
  case missingBody
  case network(String)

  public var description: String {
    switch self {
    case .invalidURL: return "Invalid URL"
    case .missingBody: return "Response body could not be decoded as text"
    case .network(let value): return value
    }
  }
}
