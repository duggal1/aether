import AetherHumanUI
import BrowserEngine
import EngineRuntime
import Foundation
import JevSearch

extension AetherEngineAdapter: BrowserSearchIntelligence {
  func jevSearch(query: String, local: [BrowserSearchSignal]) async throws -> BrowserSearchOutcome {
    let outcome = await engine.jevSearch(query: query, local: local.compactMap(\.localSignal))
    return outcome.searchOutcome
  }

  func jevCompletions(prefix: String, local: [BrowserSearchSignal], limit: Int) async throws
    -> [BrowserSearchCandidate]
  {
    let candidates = await engine.jevCompletions(
      prefix: prefix, local: local.compactMap(\.localSignal), limit: limit)
    return candidates.map(\.searchCandidate)
  }

  func jevIsConfigured() async -> Bool {
    await engine.jevAvailability().isReady
  }

  func jevUpdateKeys(typeSafeKey: String, search1APIKey: String) async {
    await engine.updateJevSearchKeys(typeSafeKey: typeSafeKey, search1APIKey: search1APIKey)
  }
}

extension AetherEngineAdapter: BrowserNativeSearchIntelligence {
  func rankHistory(query: String, pages: [BrowserSearchMemory]) async -> [UUID] {
    let candidates = pages.map {
      NativeSearchPage(id: $0.id.uuidString, title: $0.title, url: $0.url, excerpt: $0.excerpt)
    }
    let ids = await engine.runtime.rankSearchHistory(query: query, pages: candidates)
    return ids.compactMap(UUID.init(uuidString:))
  }
}

extension AetherEngineAdapter: BrowserPageTextProviding {
  func indexablePageText(pageID: String) async throws -> String {
    let source = "(() => { const root = document.querySelector('main') || document.body; return (root?.innerText || '').slice(0, 1600) })()"
    return try await engine.runtime.evaluate(pageID: page(pageID), source: source).value
  }
}

extension AetherEngineAdapter: BrowserNativeSemanticActions {
  func joinMeeting(pageID: String) async {
    guard let pageID = try? page(pageID) else { return }
    await engine.runtime.joinMeeting(pageID: pageID)
  }
}

extension BrowserSearchSignal {
  var localSignal: LocalSignal? {
    guard let address = URL(string: url), address.host != nil else { return nil }
    guard let kind = LocalSignal.Kind(rawValue: kind.rawValue) else { return nil }
    return LocalSignal(
      kind: kind, title: title, url: address, visits: visits, lastVisit: lastVisit)
  }
}

extension SearchOutcome {
  var searchOutcome: BrowserSearchOutcome {
    BrowserSearchOutcome(
      query: query, intent: intent.rawValue, confidence: intentConfidence, degraded: degraded,
      retrievalCount: retrievalCount, model: model,
      candidates: candidates.map(\.searchCandidate))
  }
}

extension SearchCandidate {
  var searchCandidate: BrowserSearchCandidate {
    BrowserSearchCandidate(
      id: id, kind: BrowserSearchCandidateKind(rawValue: kind.rawValue) ?? .web, title: title,
      subtitle: subtitle, url: url?.absoluteString, score: score, relevance: relevance)
  }
}
