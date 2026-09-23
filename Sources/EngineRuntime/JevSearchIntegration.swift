import Foundation
import JevSearch

public struct JevSearchAvailability: Sendable, Hashable {
  public let intelligence: Bool
  public let retrieval: Bool
  public let model: String

  public init(intelligence: Bool, retrieval: Bool, model: String) {
    self.intelligence = intelligence
    self.retrieval = retrieval
    self.model = model
  }

  public var isReady: Bool { intelligence }
}

extension BrowserRuntime {
  public func jevSearch(query: String, local: [LocalSignal]) async -> SearchOutcome {
    await searchIntelligence.search(query: query, local: local)
  }

  public func jevCompletions(prefix: String, local: [LocalSignal], limit: Int) async
    -> [SearchCandidate]
  {
    await searchIntelligence.completions(prefix: prefix, local: local, limit: limit)
  }

  public func jevAvailability() async -> JevSearchAvailability {
    JevSearchAvailability(
      intelligence: await searchIntelligence.intelligenceAvailable,
      retrieval: await searchIntelligence.retrievalAvailable,
      model: await searchIntelligence.modelName)
  }

  public func updateJevSearchKeys(typeSafeKey: String, search1APIKey: String) async {
    await searchIntelligence.updateKeys(typeSafeKey: typeSafeKey, search1APIKey: search1APIKey)
  }

  public func invalidateJevSearchCaches() async {
    await searchIntelligence.invalidateCaches()
  }
}
