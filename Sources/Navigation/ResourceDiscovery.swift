import DOM
import Foundation

public enum DiscoveredScript: Sendable {
  case inline(String)
  case external(URL)
}

public struct DiscoveredImage: Hashable, Sendable {
  public var nodeID: NodeID
  public var url: URL

  public init(nodeID: NodeID, url: URL) {
    self.nodeID = nodeID
    self.url = url
  }
}

public struct PageResources: Sendable {
  public var stylesheets: [URL]
  public var inlineStyles: [String]
  public var scripts: [DiscoveredScript]
  public var images: [DiscoveredImage]

  public init(
    stylesheets: [URL] = [], inlineStyles: [String] = [], scripts: [DiscoveredScript] = [],
    images: [DiscoveredImage] = []
  ) {
    self.stylesheets = stylesheets
    self.inlineStyles = inlineStyles
    self.scripts = scripts
    self.images = images
  }
}

public enum ResourceDiscovery {
  public static func discover(in document: DOMDocument, baseURL: URL) -> PageResources {
    var result = PageResources()
    for id in document.depthFirst() {
      guard let node = document.node(id), let tag = node.tagName else { continue }
      switch tag {
      case "style":
        result.inlineStyles.append(document.textContent(of: id))
      case "script":
        if let src = node.attribute("src"),
          let url = URL(string: src, relativeTo: baseURL)?.absoluteURL
        {
          result.scripts.append(.external(url))
        } else {
          result.scripts.append(.inline(document.textContent(of: id)))
        }
      case "link":
        if node.attribute("rel")?.lowercased().split(whereSeparator: { $0.isWhitespace }).contains(
          "stylesheet") == true,
          let href = node.attribute("href"),
          let url = URL(string: href, relativeTo: baseURL)?.absoluteURL
        {
          result.stylesheets.append(url)
        }
      case "img":
        if let src = node.attribute("src"),
          let url = URL(string: src, relativeTo: baseURL)?.absoluteURL
        {
          result.images.append(DiscoveredImage(nodeID: id, url: url))
        }
      default:
        break
      }
    }
    return result
  }
}
