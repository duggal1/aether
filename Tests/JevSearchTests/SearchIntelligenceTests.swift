import Foundation
import Testing

@testable import JevSearch

actor FakeTransport: HTTPPostTransport {
  private var jevResponses: [[String: Any]]
  private let searchResponse: [String: Any]
  private(set) var jevBodies: [String] = []
  private(set) var searchBodies: [String] = []

  init(jevResponses: [[String: Any]] = [], searchResponse: [String: Any] = ["results": []]) {
    self.jevResponses = jevResponses
    self.searchResponse = searchResponse
  }

  func post(_ body: Data, to endpoint: URL, bearer: String, timeout: TimeInterval) async throws
    -> Data
  {
    let text = String(decoding: body, as: UTF8.self)
    if endpoint.absoluteString.contains("systemone") {
      jevBodies.append(text)
      let response = jevResponses.isEmpty ? [:] : jevResponses.removeFirst()
      return try JSONSerialization.data(withJSONObject: response)
    }
    searchBodies.append(text)
    return try JSONSerialization.data(withJSONObject: searchResponse)
  }
}

private func configuration(
  intelligence: Bool = true, retrieval: Bool = true, service: String? = nil
) -> JevConfiguration {
  JevConfiguration(
    typeSafeKey: intelligence ? "test-key" : "",
    search1APIKey: retrieval ? "test-search-key" : "",
    model: "jev-test", searchService: service, resultLimit: 5)
}

private func choiceAnswer(_ value: String, _ confidence: Double) -> [String: Any] {
  ["type": "choice", "choice": value, "confidence": confidence, "probabilities": [value: confidence]]
}

private func noulAnswer(_ value: Double) -> [String: Any] {
  ["type": "noul", "noul": value]
}

private func jevPage(_ answers: [String: Any]) -> [String: Any] {
  ["model": "jev-test", "answers": answers, "usage": ["input_tokens": 10, "output_tokens": 4]]
}

private let appleSignals = [
  LocalSignal(
    kind: .history, title: "Apple", url: URL(string: "https://www.apple.com/")!, visits: 4,
    lastVisit: 1_700_000_000)
]

struct DotEnvTests {
  @Test func parsesCommentsQuotesAndExport() {
    let values = DotEnv.parse(
      """
      # comment
      TYPESAFE_API_KEY=abc123

      export SEARCH1API_API_KEY='quoted value'
      JEV_MODEL="jev-latest"
      BROKEN
      EMPTY=
      """)
    #expect(values["TYPESAFE_API_KEY"] == "abc123")
    #expect(values["SEARCH1API_API_KEY"] == "quoted value")
    #expect(values["JEV_MODEL"] == "jev-latest")
    #expect(values["EMPTY"] == "")
    #expect(values["BROKEN"] == nil)
  }

  @Test func configurationReadsDocumentedKeys() {
    let loaded = JevConfiguration.load([
      "TYPESAFE_API_KEY": "ts", "SEARCH1API_API_KEY": "s1", "JEV_MODEL": "jev-9",
      "JEV_SEARCH_RESULTS": "3", "SEARCH1API_SERVICE": "duckduckgo",
    ])
    #expect(loaded.typeSafeKey == "ts")
    #expect(loaded.search1APIKey == "s1")
    #expect(loaded.model == "jev-9")
    #expect(loaded.resultLimit == 3)
    #expect(loaded.searchService == "duckduckgo")
    #expect(loaded.hasIntelligence)
    #expect(loaded.hasRetrieval)
  }

  @Test func configurationDefaultsToDocumentedEndpoints() {
    let loaded = JevConfiguration.load([:])
    #expect(loaded.typeSafeEndpoint.absoluteString == "https://api.typesafe.ai/v1/systemone")
    #expect(loaded.searchEndpoint.absoluteString == "https://api.search1api.com/search")
    #expect(loaded.model == "jev-latest")
    #expect(loaded.hasIntelligence == false)
    #expect(loaded.searchService == nil)
  }
}

struct SearchInputTests {
  @Test func classifiesAddressesDeterministically() {
    #expect(SearchInput.directURL("https://github.com/x/y")?.host == "github.com")
    #expect(SearchInput.directURL("apple.com")?.absoluteString == "https://apple.com")
    #expect(SearchInput.directURL("localhost:3000")?.absoluteString == "http://localhost:3000")
    #expect(SearchInput.directURL("how to cook rice") == nil)
    #expect(SearchInput.directURL("apple") == nil)
  }

  @Test func matchesSharedAddressRules() {
    #expect(SearchInput.directURL("youtube.com/watch?v=dQw4w9WgXcQ")?.absoluteString
      == "https://youtube.com/watch?v=dQw4w9WgXcQ")
    #expect(SearchInput.directURL("127.0.0.1:8765/")?.absoluteString == "http://127.0.0.1:8765/")
    #expect(SearchInput.directURL("192.168.1.1")?.absoluteString == "http://192.168.1.1")
    #expect(SearchInput.directURL("[::1]:3000")?.absoluteString == "http://[::1]:3000")
    #expect(SearchInput.directURL("hi") == nil)
    #expect(SearchInput.directURL("v1.2") == nil)
    #expect(SearchInput.directURL("https://person:secret@example.com/") == nil)
  }

  @Test func guessesOneWordDomainsOnly() {
    #expect(SearchInput.domainGuesses("apple", limit: 3) == ["apple.com", "apple.org", "apple.io"])
    #expect(SearchInput.domainGuesses("two words", limit: 3).isEmpty)
    #expect(SearchInput.domainGuesses("a", limit: 3).isEmpty)
    #expect(SearchInput.domainGuesses("apple.com", limit: 3).isEmpty)
    #expect(SearchInput.domainGuesses("café", limit: 3).isEmpty)
  }

  @Test func recencyDecaysWithHalfLife() {
    let now: Double = 1_700_000_000
    #expect(SearchIntelligence.recency(now, now: now) == 1)
    #expect(abs(SearchIntelligence.recency(now - 30 * 86_400, now: now) - 0.5) < 0.001)
    #expect(SearchIntelligence.recency(0, now: now) == 0)
    #expect(SearchIntelligence.recency(now + 100, now: now) == 0)
  }
}

struct JevClientTests {
  @Test func sendsTypedQuestionsInDocumentedShape() async throws {
    let transport = FakeTransport(jevResponses: [
      jevPage(["intent": choiceAnswer("informational", 0.7)])
    ])
    let client = JevClient(configuration: configuration(), transport: transport)
    _ = try await client.ask(
      state: RequestState(request: "swift"),
      questions: [
        "intent": .choice("What does the person want?", [
          "informational": "Find information", "navigational": "Open a site",
        ]),
        "urgent": .noul("Is it urgent?", yes: "Yes", no: "No"),
      ])
    let body = await transport.jevBodies[0]
    #expect(body.contains("\"model\":\"jev-test\""))
    #expect(body.contains("\"state\":{\"request\":\"swift\"}"))
    #expect(body.contains("\"type\":\"choice\""))
    #expect(body.contains("\"type\":\"noul\""))
    #expect(body.contains("\"true\":\"Yes\""))
  }

  @Test func decodesAllThreePrimitiveAnswers() async throws {
    let transport = FakeTransport(jevResponses: [
      jevPage([
        "intent": choiceAnswer("local", 0.81),
        "quality": ["type": "score", "score": 2.0, "confidence": 0.9, "probabilities": ["2": 0.9]],
        "relevant": noulAnswer(0.93),
      ])
    ])
    let client = JevClient(configuration: configuration(), transport: transport)
    let response = try await client.ask(state: RequestState(request: "x"), questions: ["intent": .choice("q", [:])])
    #expect(response.model == "jev-test")
    #expect(response.answers["intent"]?.choice == "local")
    #expect(response.answers["intent"]?.confidence == 0.81)
    #expect(response.answers["quality"]?.score == 2.0)
    #expect(response.answers["relevant"]?.noul == 0.93)
    #expect(response.usage?.inputTokens == 10)
  }

  @Test func refusesWhenUnconfigured() async {
    let client = JevClient(
      configuration: configuration(intelligence: false), transport: FakeTransport())
    await #expect(throws: JevError.self) {
      _ = try await client.ask(state: RequestState(request: "x"), questions: ["intent": .choice("q", [:])])
    }
  }
}

struct Search1APIClientTests {
  @Test func sendsDocumentedBodyAndDecodesResults() async throws {
    let transport = FakeTransport(searchResponse: [
      "searchParameters": ["query": "swift", "search_service": "google"],
      "results": [
        ["title": "Swift", "link": "https://swift.org", "snippet": "The Swift language"],
        ["title": "Only content", "link": "https://example.com", "content": "Body text"],
      ],
    ])
    let client = Search1APIClient(configuration: configuration(service: "google"), transport: transport)
    let results = try await client.search(query: "swift", limit: 5)
    #expect(results.count == 2)
    #expect(results[0].url?.absoluteString == "https://swift.org")
    #expect(results[0].snippet == "The Swift language")
    #expect(results[1].snippet == "Body text")
    let body = await transport.searchBodies[0]
    #expect(body.contains("\"search_service\":\"google\""))
    #expect(body.contains("\"max_results\":5"))
    #expect(body.contains("\"query\":\"swift\""))
  }

  @Test func omitsSearchServiceSoRetrievalStaysMultiEngine() async throws {
    let transport = FakeTransport(searchResponse: ["results": []])
    let client = Search1APIClient(configuration: configuration(), transport: transport)
    _ = try await client.search(query: "swift", limit: 5)
    let body = await transport.searchBodies[0]
    #expect(body.contains("search_service") == false)
    #expect(body.contains("\"query\":\"swift\""))
    #expect(body.contains("\"max_results\":5"))
  }

  @Test func sendsSearchServiceOnlyWhenExplicitlyPinned() async throws {
    var pinned = configuration()
    pinned.searchService = "duckduckgo"
    let transport = FakeTransport(searchResponse: ["results": []])
    let client = Search1APIClient(configuration: pinned, transport: transport)
    _ = try await client.search(query: "swift", limit: 5)
    #expect(await transport.searchBodies[0].contains("\"search_service\":\"duckduckgo\""))
  }

  @Test func surfacesApiFailures() async {
    let transport = FakeTransport(searchResponse: ["ok": false, "message": "quota exceeded"])
    let client = Search1APIClient(configuration: configuration(), transport: transport)
    await #expect(throws: JevError.self) {
      _ = try await client.search(query: "swift", limit: 5)
    }
  }
}

struct SearchIntelligenceTests {
  private let now: Double = 1_700_000_000

  @Test func directAddressSkipsTheModelEntirely() async {
    let transport = FakeTransport()
    let search = SearchIntelligence(configuration: configuration(), transport: transport)
    let outcome = await search.search(query: "apple.com", now: now)
    #expect(outcome.intent == .navigational)
    #expect(outcome.candidates.first?.kind == .navigate)
    #expect(outcome.candidates.first?.url?.absoluteString == "https://apple.com")
    #expect(await transport.jevBodies.isEmpty)
  }

  @Test func navigationalIntentPinsTheJudgedDomain() async {
    let transport = FakeTransport(jevResponses: [
      jevPage([
        "intent": choiceAnswer("navigational", 0.92),
        "domain": choiceAnswer("apple.com", 0.88),
        "local_0": noulAnswer(0.95),
      ]),
      jevPage(["relevant_0": noulAnswer(0.9)]),
    ])
    let search = SearchIntelligence(configuration: configuration(), transport: transport)
    let outcome = await search.search(query: "apple", local: appleSignals, now: now)
    #expect(outcome.intent == .navigational)
    #expect(outcome.intentConfidence == 0.92)
    #expect(outcome.degraded == false)
    #expect(outcome.primary?.url?.absoluteString == "https://apple.com")
    #expect(outcome.primary?.kind == .navigate)
    #expect(outcome.candidates.contains { $0.kind == .history })
    let body = await transport.jevBodies[0]
    #expect(body.contains("apple.com"))
    #expect(body.contains("local_0"))
  }

  @Test func weakDomainJudgmentIsNotPinned() async {
    let transport = FakeTransport(jevResponses: [
      jevPage([
        "intent": choiceAnswer("navigational", 0.9),
        "domain": choiceAnswer("apple.com", 0.41),
      ]),
      jevPage([:]),
    ])
    let search = SearchIntelligence(configuration: configuration(), transport: transport)
    let outcome = await search.search(query: "apple", now: now)
    #expect(outcome.candidates.contains { $0.kind == .navigate } == false)
  }

  @Test func unevaluatedIntentDoesNotPin() async {
    let transport = FakeTransport(jevResponses: [
      jevPage([
        "intent": choiceAnswer("informational", 0.9),
        "domain": choiceAnswer("apple.com", 0.95),
      ]),
      jevPage([:]),
    ])
    let search = SearchIntelligence(configuration: configuration(), transport: transport)
    let outcome = await search.search(query: "apple", now: now)
    #expect(outcome.intent == .informational)
    #expect(outcome.candidates.contains { $0.kind == .navigate } == false)
  }

  @Test func relevanceReordersWebResults() async {
    let transport = FakeTransport(
      jevResponses: [
        jevPage(["intent": choiceAnswer("informational", 0.8)]),
        jevPage(["relevant_0": noulAnswer(0.05), "relevant_1": noulAnswer(0.95)]),
      ],
      searchResponse: [
        "results": [
          ["title": "Weak", "link": "https://weak.example", "snippet": "not about it"],
          ["title": "Strong", "link": "https://strong.example", "snippet": "exactly it"],
        ]
      ])
    let search = SearchIntelligence(configuration: configuration(), transport: transport)
    let outcome = await search.search(query: "swift concurrency", now: now)
    let web = outcome.candidates.filter { $0.kind == .web }
    #expect(web.count == 1)
    #expect(web.first?.title == "Strong")
    #expect(outcome.candidates.contains { $0.title == "Weak" } == false)
    let body = await transport.jevBodies[1]
    #expect(body.contains("relevant_0"))
    #expect(body.contains("relevant_1"))
  }

  @Test func irrelevantResultsAreDropped() async {
    let transport = FakeTransport(
      jevResponses: [
        jevPage(["intent": choiceAnswer("informational", 0.8)]),
        jevPage(["relevant_0": noulAnswer(0.02)]),
      ],
      searchResponse: [
        "results": [["title": "Junk", "link": "https://junk.example", "snippet": "ads"]]
      ])
    let search = SearchIntelligence(configuration: configuration(), transport: transport)
    let outcome = await search.search(query: "anything", now: now)
    #expect(outcome.candidates.contains { $0.kind == .web } == false)
    #expect(outcome.candidates.last?.kind == .google)
  }

  @Test func googleFallbackAppearsWhenJevCannotServe() async {
    let search = SearchIntelligence(
      configuration: configuration(intelligence: false, retrieval: false), transport: FakeTransport())
    let outcome = await search.search(query: "swift concurrency", now: now)
    #expect(outcome.degraded)
    #expect(outcome.candidates.last?.kind == .google)
    #expect(
      outcome.candidates.last?.url?.absoluteString
        == "https://www.google.com/search?q=swift%20concurrency")
  }

  @Test func googleFallbackIsAbsentWhenJevServesResults() async {
    let transport = FakeTransport(
      jevResponses: [
        jevPage(["intent": choiceAnswer("informational", 0.8)]),
        jevPage(["relevant_0": noulAnswer(0.9)]),
      ],
      searchResponse: [
        "results": [["title": "Swift", "link": "https://swift.org", "snippet": "the language"]]
      ])
    let search = SearchIntelligence(configuration: configuration(), transport: transport)
    let outcome = await search.search(query: "swift", now: now)
    #expect(outcome.degraded == false)
    #expect(outcome.candidates.contains { $0.kind == .google } == false)
    #expect(outcome.candidates.first?.kind == .web)
  }

  @Test func googleFallbackCoversAnEmptyResultSet() async {
    let transport = FakeTransport(
      jevResponses: [jevPage(["intent": choiceAnswer("informational", 0.8)])],
      searchResponse: ["results": []])
    let search = SearchIntelligence(configuration: configuration(), transport: transport)
    let outcome = await search.search(query: "an obscure phrase", now: now)
    #expect(outcome.degraded == false)
    #expect(outcome.candidates.count == 1)
    #expect(outcome.candidates.first?.kind == .google)
  }

  @Test func missingKeysDegradeInsteadOfFailing() async {
    let transport = FakeTransport()
    let search = SearchIntelligence(
      configuration: configuration(intelligence: false, retrieval: false), transport: transport)
    let outcome = await search.search(query: "apple", local: appleSignals, now: now)
    #expect(outcome.degraded)
    #expect(outcome.retrievalCount == 0)
    #expect(outcome.candidates.contains { $0.kind == .history })
    #expect(await transport.jevBodies.isEmpty)
    #expect(outcome.candidates.last?.kind == .google)
  }

  @Test func completionsOfferJudgedDomainBeforeLocalMatches() async {
    let transport = FakeTransport(jevResponses: [
      jevPage(["domain": choiceAnswer("apple.com", 0.9)])
    ])
    let search = SearchIntelligence(configuration: configuration(), transport: transport)
    let completions = await search.completions(
      prefix: "apple", local: appleSignals, now: now)
    #expect(completions.first?.url?.absoluteString == "https://apple.com")
    #expect(completions.contains { $0.kind == .history })
  }

  @Test func completionsFallsBackToLocalOnlyWhenUnconfigured() async {
    let search = SearchIntelligence(
      configuration: configuration(intelligence: false), transport: FakeTransport())
    let completions = await search.completions(prefix: "app", local: appleSignals, now: now)
    #expect(completions.count == 1)
    #expect(completions.first?.kind == .history)
  }

  @Test func webResultsAreCachedPerQuery() async {
    let transport = FakeTransport(searchResponse: [
      "results": [["title": "Swift", "link": "https://swift.org", "snippet": "x"]]
    ])
    let search = SearchIntelligence(configuration: configuration(), transport: transport)
    _ = await search.search(query: "swift", now: now)
    _ = await search.search(query: "swift", now: now)
    #expect(await transport.searchBodies.count == 1)
  }
}
