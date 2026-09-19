import DOM
import EngineCore
import EngineRuntime
import Foundation

public struct PageTextMatch: Hashable, Sendable {
  public let node: NodeID
  public let characterOffset: Int
  public let characterLength: Int
  public let text: String
  public let bounds: Rect?
}

public enum PageTextSearch {
  public static func find(
    in snapshot: PageSnapshot, query: String, caseSensitive: Bool = false,
    maximumMatches: Int = 100
  ) -> [PageTextMatch] {
    guard !query.isEmpty, maximumMatches > 0 else { return [] }
    let limit = min(maximumMatches, 1_000)
    let byID = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
    let excludedTags: Set<String> = ["head", "script", "style", "template", "noscript"]
    let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
    var matches: [PageTextMatch] = []
    for node in snapshot.nodes where node.kind == "text" && node.visible {
      guard let text = node.text, !text.isEmpty else { continue }
      var ancestor = node.parent
      var exposed = true
      while let parentID = ancestor {
        guard let parent = byID[parentID], parent.visible,
          !excludedTags.contains(parent.tag?.lowercased() ?? "")
        else {
          exposed = false
          break
        }
        ancestor = parent.parent
      }
      guard exposed else { continue }
      var cursor = text.startIndex
      while cursor < text.endIndex && matches.count < limit {
        guard let found = text.range(
          of: query, options: options, range: cursor..<text.endIndex
        ) else { break }
        matches.append(PageTextMatch(
          node: node.id, characterOffset: text.distance(from: text.startIndex, to: found.lowerBound),
          characterLength: text.distance(from: found.lowerBound, to: found.upperBound),
          text: String(text[found]), bounds: node.bounds))
        cursor = found.upperBound
      }
      if matches.count == limit { break }
    }
    return matches
  }
}
