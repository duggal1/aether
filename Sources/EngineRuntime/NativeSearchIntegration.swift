import Foundation
import JevSearch

public struct NativeSearchPage: Sendable, Hashable {
  public let id: String
  public let title: String
  public let url: String
  public let excerpt: String

  public init(id: String, title: String, url: String, excerpt: String) {
    self.id = id
    self.title = title
    self.url = url
    self.excerpt = excerpt
  }
}

extension BrowserRuntime {
  public func rankSearchHistory(query: String, pages: [NativeSearchPage]) async -> [String] {
    let candidates = pages.prefix(24).map { page in
      let host = URL(string: page.url)?.host ?? ""
      return SemanticHistoryCandidate(
        id: page.id, title: String(page.title.prefix(180)), host: String(host.prefix(120)),
        excerpt: String(page.excerpt.prefix(500)))
    }
    let scores = await semanticSignalService.rankHistory(query: query, candidates: candidates)
    return scores.prefix(5).map(\.id)
  }
}
