import Foundation
import Testing

@testable import JevSearch

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["JEV_LIVE"] == "1"))
struct JevLiveTests {
  @Test func liveSearchUsesJevAndRealRetrieval() async throws {
    let configuration = JevConfiguration.load()
    try #require(configuration.hasIntelligence, "TYPESAFE_API_KEY is missing from .env")
    try #require(configuration.hasRetrieval, "SEARCH1API_API_KEY is missing from .env")

    let search = SearchIntelligence(configuration: configuration)
    let now = Date().timeIntervalSince1970
    let outcome = await search.search(
      query: "Swift structured concurrency task groups",
      local: [
        LocalSignal(
          kind: .bookmark, title: "Swift.org", url: URL(string: "https://swift.org")!, visits: 3,
          lastVisit: now)
      ],
      now: now)

    print("LIVE model=\(outcome.model ?? "none") intent=\(outcome.intent) confidence=\(outcome.intentConfidence) retrieved=\(outcome.retrievalCount) answers=\(outcome.answers) degraded=\(outcome.degraded)")
    for candidate in outcome.candidates.prefix(5) {
      print(
        "LIVE [\(candidate.kind.rawValue)] score=\(String(format: "%.2f", candidate.score)) rel=\(String(format: "%.2f", candidate.relevance)) \(candidate.title.prefix(70)) -> \(candidate.url?.absoluteString ?? "-")"
      )
    }

    #expect(outcome.degraded == false)
    #expect(outcome.model?.isEmpty == false)
    #expect(outcome.retrievalCount > 0)
    #expect(outcome.answers > 0)
    #expect(outcome.candidates.contains { $0.kind == .web })
  }

  @Test func liveRetrievalIsMultiEngineByDefault() async throws {
    let configuration = JevConfiguration.load()
    try #require(configuration.hasRetrieval, "SEARCH1API_API_KEY is missing from .env")
    #expect(configuration.searchService == nil)

    let client = Search1APIClient(configuration: configuration)
    let results = try await client.search(query: "Swift concurrency", limit: 5)
    print("LIVE retrieval returned \(results.count) results, first host=\(results.first?.host ?? "-")")
    #expect(results.isEmpty == false)
  }

  @Test func liveRelevanceDiagnostic() async throws {
    let configuration = JevConfiguration.load()
    try #require(configuration.hasIntelligence && configuration.hasRetrieval)
    let transport = URLSessionTransport()
    let query = "Swift structured concurrency task groups"
    let results = try await Search1APIClient(configuration: configuration, transport: transport)
      .search(query: query, limit: 7)
    print("LIVE diag retrieved=\(results.count)")
    var questions: [String: JevQuestion] = [:]
    for (index, result) in results.enumerated() {
      questions["relevant_\(index)"] = .noul(
        "The person's request is: \(query). Is this search result relevant to that request? Result title: \(result.title). Result address: \(result.link). Result summary: \(result.snippet.prefix(320))",
        yes: "The result is about what the person asked for",
        no: "The result is off topic, an advertisement, or a generic hub page")
    }
    let response = try await JevClient(configuration: configuration, transport: transport).ask(
      state: RequestState(request: query), questions: questions)
    for index in results.indices {
      let value = response.answers["relevant_\(index)"]?.noul ?? -1
      print(
        "LIVE diag rel[\(index)] noul=\(value) title=\(results[index].title.prefix(45)) snippet=\(results[index].snippet.count)chars"
      )
    }
  }

  @Test func liveDomainJudgmentReturnsAConfidence() async throws {
    let configuration = JevConfiguration.load()
    try #require(configuration.hasIntelligence, "TYPESAFE_API_KEY is missing from .env")

    let search = SearchIntelligence(configuration: configuration)
    let outcome = await search.search(query: "apple", now: Date().timeIntervalSince1970)
    print("LIVE apple intent=\(outcome.intent) confidence=\(outcome.intentConfidence) primary=\(outcome.primary?.url?.absoluteString ?? "-")")

    #expect(outcome.intentConfidence > 0)
    #expect(outcome.candidates.isEmpty == false)
  }
}
