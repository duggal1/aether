import EngineRuntime
import Foundation
import JevSearch

extension NativeBrowserEngine {
  public func jevSearch(query: String, local: [LocalSignal]) async -> SearchOutcome {
    await runtime.jevSearch(query: query, local: local)
  }

  public func jevCompletions(
    prefix: String, local: [LocalSignal], limit: Int = SearchTuning.completionLimit
  ) async -> [SearchCandidate] {
    await runtime.jevCompletions(prefix: prefix, local: local, limit: limit)
  }

  public func jevAvailability() async -> JevSearchAvailability {
    await runtime.jevAvailability()
  }

  public func updateJevSearchKeys(typeSafeKey: String, search1APIKey: String) async {
    await runtime.updateJevSearchKeys(typeSafeKey: typeSafeKey, search1APIKey: search1APIKey)
  }

  public func invalidateJevSearchCaches() async {
    await runtime.invalidateJevSearchCaches()
  }
}
