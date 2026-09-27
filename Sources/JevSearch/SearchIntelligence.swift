import Foundation

struct RequestState: Encodable, Sendable {
  let request: String
}

public enum SearchInput {
  public static func directURL(_ raw: String) -> URL? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme), url.host != nil, url.user == nil
    {
      return url
    }
    guard !text.contains("://"), !text.contains(where: \.isWhitespace), !text.contains("@")
    else { return nil }
    if isLocalhost(text) { return URL(string: "http://" + text) }
    guard let candidate = URL(string: "https://" + text),
      let host = candidate.host, !host.isEmpty, candidate.user == nil
    else { return nil }
    if host.contains(":") || isIPv4(host) { return URL(string: "http://" + text) }
    guard isDomain(host) else { return nil }
    return candidate
  }

  public static func isLocalhost(_ text: String) -> Bool {
    let lower = text.lowercased()
    return lower == "localhost"
      || lower.hasPrefix("localhost:")
      || lower.hasPrefix("localhost/")
      || lower.hasPrefix("localhost?")
      || lower.hasPrefix("localhost#")
  }

  static func isIPv4(_ host: String) -> Bool {
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return false }
    for part in parts {
      guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isNumber }),
        let value = Int(part), value <= 255
      else { return false }
      if part.count > 1 && part.hasPrefix("0") { return false }
    }
    return true
  }

  static func isDomain(_ host: String) -> Bool {
    let clean = host.hasSuffix(".") ? String(host.dropLast()) : host
    guard clean.count <= 253 else { return false }
    let labels = clean.split(separator: ".", omittingEmptySubsequences: false)
    guard labels.count >= 2 else { return false }
    for label in labels {
      guard !label.isEmpty, label.count <= 63,
        let first = label.first, let last = label.last,
        first.isLetter || first.isNumber, last.isLetter || last.isNumber,
        label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
      else { return false }
    }
    guard let tld = labels.last else { return false }
    if tld.lowercased().hasPrefix("xn--") { return tld.count > 4 }
    return tld.count >= 2 && tld.allSatisfy({ $0.isLetter })
  }

  static func domainGuesses(_ text: String, limit: Int) -> [String] {
    guard limit > 0, !text.contains(where: \.isWhitespace), !text.contains("."), text.count >= 2
    else { return [] }
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
    guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return [] }
    let token = text.lowercased()
    return [".com", ".org", ".io", ".app", ".ai", ".dev"].prefix(limit).map { token + $0 }
  }
}

public actor SearchIntelligence {
  private var configuration: JevConfiguration
  private let semanticSignals: SemanticSignalService
  private var retrieval: Search1APIClient
  private let transport: any HTTPPostTransport
  private var cachedResults: [String: (results: [WebSearchResult], storedAt: Double)] = [:]
  private var resultOrder: [String] = []
  private var cachedGuesses: [String: SearchCandidate] = [:]
  private var guessOrder: [String] = []

  public init(
    configuration: JevConfiguration = .load(),
    transport: any HTTPPostTransport = URLSessionTransport(),
    semanticSignals: SemanticSignalService? = nil
  ) {
    self.configuration = configuration
    self.transport = transport
    self.semanticSignals = semanticSignals
      ?? SemanticSignalService(configuration: configuration, transport: transport)
    self.retrieval = Search1APIClient(configuration: configuration, transport: transport)
  }

  public func updateKeys(typeSafeKey: String, search1APIKey: String) async {
    let environment = JevConfiguration.load()
    configuration.typeSafeKey = typeSafeKey.isEmpty ? environment.typeSafeKey : typeSafeKey
    configuration.search1APIKey = search1APIKey.isEmpty ? environment.search1APIKey : search1APIKey
    await semanticSignals.updateKeys(typeSafeKey: typeSafeKey, search1APIKey: search1APIKey)
    retrieval = Search1APIClient(configuration: configuration, transport: transport)
    invalidateCaches()
  }

  public var intelligenceAvailable: Bool { configuration.hasIntelligence }
  public var retrievalAvailable: Bool { configuration.hasRetrieval }
  public var modelName: String { configuration.model }

  public func search(
    query raw: String, local: [LocalSignal] = [],
    now: Double = Date().timeIntervalSince1970
  ) async -> SearchOutcome {
    let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return .empty("") }

    if let direct = SearchInput.directURL(query) {
      return SearchOutcome(
        query: query, intent: .navigational, intentConfidence: 1,
        candidates: [
          SearchCandidate(
            id: "direct", kind: .navigate, title: direct.host ?? query, subtitle: "Open address",
            url: direct, relevance: 1, confidence: 1, score: 4)
        ],
        model: nil, degraded: false, retrievalCount: 0, answers: 0)
    }

    let signals = Array(local.prefix(SearchTuning.maximumLocalSignals))
    let guesses = SearchInput.domainGuesses(query, limit: SearchTuning.maximumDomainGuesses)

    let retrievalTask = Task { await self.webResults(query) }
    let assessment = await assess(query: query, signals: signals, guesses: guesses)
    let retrieved = await retrievalTask.value

    var candidates: [SearchCandidate] = []
    if let pinned = assessment.pinned { candidates.append(pinned) }
    for (index, signal) in signals.enumerated() {
      let relevance = assessment.local[index] ?? 0
      candidates.append(
        Self.localCandidate(signal, index: index, relevance: relevance, now: now))
    }

    let ranked = Array(retrieved.prefix(SearchTuning.maximumRankedResults))
    var answers = assessment.answers
    var model = assessment.model
    var degraded = assessment.degraded
    if configuration.hasIntelligence, !ranked.isEmpty {
      let scored = await relevanceScores(query: query, results: ranked)
      answers += scored.answers
      if model == nil { model = scored.model }
      for (index, result) in ranked.enumerated() {
        guard let url = result.url else { continue }
        let relevance = scored.scores[index] ?? Self.positionFallback(index)
        guard relevance >= SearchTuning.minimumRelevance else { continue }
        candidates.append(
          Self.webCandidate(result, index: index, url: url, relevance: relevance))
      }
    } else {
      for (index, result) in ranked.enumerated() {
        guard let url = result.url else { continue }
        let relevance = Self.positionFallback(index)
        guard relevance >= SearchTuning.minimumRelevance else { continue }
        candidates.append(
          Self.webCandidate(result, index: index, url: url, relevance: relevance))
      }
    }

    if !configuration.hasIntelligence { degraded = true }

    var ordered = Self.ordered(candidates)
    // Google is offered on every search, not only when Jev cannot serve.
    //
    // Jev judges and ranks; it cannot retrieve the web, and it cannot answer a
    // question it misread. Leaving Google out of a search that succeeded meant
    // the one escape hatch a person has — take the same words to a search
    // engine — was withdrawn exactly when they were most likely to want it, and
    // nothing in the results said so. It sits last, below everything Jev was
    // confident about, so the intelligence leads and the fallback follows.
    if let fallback = Self.googleFallback(query) {
      ordered.append(fallback)
    }
    return SearchOutcome(
      query: query, intent: assessment.intent, intentConfidence: assessment.intentConfidence,
      candidates: ordered, model: model, degraded: degraded,
      retrievalCount: retrieved.count, answers: answers)
  }

  public func completions(
    prefix raw: String, local: [LocalSignal] = [], limit: Int = SearchTuning.completionLimit,
    now: Double = Date().timeIntervalSince1970
  ) async -> [SearchCandidate] {
    let prefix = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prefix.isEmpty, limit > 0 else { return [] }
    var candidates = localMatches(prefix: prefix, local: local, now: now)
    let token = prefix.lowercased()
    if !token.contains(where: \.isWhitespace), !token.contains(".") {
      if let guess = await guessCandidate(token: token) { candidates.insert(guess, at: 0) }
    }
    return Array(Self.ordered(candidates).prefix(limit))
  }

  public func invalidateCaches() {
    cachedResults.removeAll()
    resultOrder.removeAll()
    cachedGuesses.removeAll()
    guessOrder.removeAll()
  }

  private struct Assessment: Sendable {
    var intent: SearchIntent = .informational
    var intentConfidence: Double = 0
    var pinned: SearchCandidate?
    var local: [Int: Double] = [:]
    var model: String?
    var answers: Int = 0
    var degraded: Bool = false
  }

  private func assess(query: String, signals: [LocalSignal], guesses: [String]) async -> Assessment {
    var result = Assessment()
    guard configuration.hasIntelligence else {
      result.degraded = true
      return result
    }
    var questions: [String: JevQuestion] = [
      "intent": .choice(
        "What is the person most likely trying to do when they type this into a browser address bar?",
        [
          "navigational": "Go to one specific website they already have in mind",
          "informational": "Find information across the web",
          "local": "Return to a page they already visited or saved",
        ])
    ]
    if !guesses.isEmpty {
      var options: [String: String] = [:]
      for guess in guesses { options[guess] = "The website \(guess)" }
      options["none"] = "None of these; the person is not looking for a one-word website"
      questions["domain"] = .choice(
        "Which website is this person most likely looking for?", options)
    }
    for (index, signal) in signals.enumerated() {
      questions["local_\(index)"] = .noul(
        "The person's request is: \(query). Does this saved location directly satisfy that request? Location title: \(signal.title). Location address: \(signal.url.absoluteString)",
        yes: "It is the page or site the request refers to",
        no: "It is unrelated, or only loosely related")
    }
    do {
      let response = try await semanticSignals.ask(
        state: RequestState(request: query), questions: questions)
      result.model = response.model
      result.answers = response.answers.count
      if let answer = response.answers["intent"], let choice = answer.choice,
        let intent = SearchIntent(rawValue: choice) {
        result.intent = intent
        result.intentConfidence = answer.confidence ?? 0
      }
      if let answer = response.answers["domain"], let choice = answer.choice, choice != "none",
        guesses.contains(choice), let url = URL(string: "https://" + choice) {
        let confidence = answer.confidence ?? 0
        if result.intent == .navigational, confidence >= SearchTuning.confidenceFloor {
          result.pinned = SearchCandidate(
            id: "guess:" + choice, kind: .navigate, title: choice, subtitle: "Likely website",
            url: url, completion: "https://" + choice, relevance: 1, confidence: confidence,
            score: 3.5 + max(0, confidence - SearchTuning.confidenceFloor) * 0.5)
        }
      }
      for index in signals.indices {
        if let answer = response.answers["local_\(index)"], let value = answer.noul {
          result.local[index] = value
        }
      }
    } catch {
      result.degraded = true
    }
    return result
  }

  private func relevanceScores(query: String, results: [WebSearchResult]) async -> (
    scores: [Int: Double], answers: Int, model: String?
  ) {
    guard configuration.hasIntelligence, !results.isEmpty else { return ([:], 0, nil) }
    var questions: [String: JevQuestion] = [:]
    for (index, result) in results.enumerated() {
      questions["relevant_\(index)"] = .noul(
        "The person's request is: \(query). Is this search result relevant to that request? Result title: \(result.title). Result address: \(result.link). Result summary: \(result.snippet.prefix(320))",
        yes: "The result is about what the person asked for",
        no: "The result is off topic, an advertisement, or a generic hub page")
    }
    do {
      let response = try await semanticSignals.ask(
        state: RequestState(request: query), questions: questions)
      var scores: [Int: Double] = [:]
      for index in results.indices {
        if let answer = response.answers["relevant_\(index)"], let value = answer.noul {
          scores[index] = value
        }
      }
      return (scores, response.answers.count, response.model)
    } catch {
      return ([:], 0, nil)
    }
  }

  private func webResults(_ query: String) async -> [WebSearchResult] {
    guard configuration.hasRetrieval else { return [] }
    let key = (configuration.searchService ?? "multi") + "|" + query.lowercased()
    if let entry = cachedResults[key],
      Date().timeIntervalSince1970 - entry.storedAt < SearchTuning.cacheLifetime {
      return entry.results
    }
    do {
      let results = try await retrieval.search(query: query, limit: configuration.resultLimit)
      store(results, key: key)
      return results
    } catch {
      return []
    }
  }

  private func localMatches(prefix: String, local: [LocalSignal], now: Double) -> [SearchCandidate] {
    let needle = prefix.lowercased()
    var scored: [SearchCandidate] = []
    for (index, signal) in local.enumerated() {
      let title = signal.title.lowercased()
      let host = signal.host.lowercased()
      let address = signal.url.absoluteString.lowercased()
      let strength: Double
      if host.hasPrefix(needle) { strength = 3 }
      else if title.hasPrefix(needle) { strength = 2.5 }
      else if title.contains(needle) || address.contains(needle) { strength = 1.5 }
      else { continue }
      let score =
        strength + Self.recency(signal.lastVisit, now: now) * SearchTuning.recencyWeight
        + min(Double(signal.visits), SearchTuning.visitCeiling) * SearchTuning.visitWeight
      scored.append(
        SearchCandidate(
          id: "local:\(index):\(signal.host)", kind: Self.kind(signal.kind),
          title: signal.title.isEmpty ? signal.host : signal.title, subtitle: signal.host,
          url: signal.url, completion: signal.url.absoluteString, relevance: 0, confidence: 0,
          score: score))
    }
    return scored
  }

  private func guessCandidate(token: String) async -> SearchCandidate? {
    guard configuration.hasIntelligence else { return nil }
    if let cached = cachedGuesses[token] { return cached }
    let guesses = SearchInput.domainGuesses(token, limit: SearchTuning.maximumDomainGuesses)
    guard !guesses.isEmpty else { return nil }
    var options: [String: String] = [
      "none": "Not a website name; the person wants a search instead"
    ]
    for guess in guesses { options[guess] = "The website \(guess)" }
    let questions: [String: JevQuestion] = [
      "domain": .choice(
        "Someone typed this single word into a browser address bar. Which website are they most likely looking for?",
        options)
    ]
    guard
      let response = try? await semanticSignals.ask(
        state: RequestState(request: token), questions: questions),
      let answer = response.answers["domain"], let choice = answer.choice, choice != "none",
      guesses.contains(choice), let url = URL(string: "https://" + choice)
    else { return nil }
    let confidence = answer.confidence ?? 0
    guard confidence >= SearchTuning.confidenceFloor else { return nil }
    let candidate = SearchCandidate(
      id: "guess:" + choice, kind: .navigate, title: choice, subtitle: "Likely website", url: url,
      completion: "https://" + choice, relevance: 1, confidence: confidence,
      score: 3.5 + max(0, confidence - SearchTuning.confidenceFloor) * 0.5)
    storeGuess(candidate, token: token)
    return candidate
  }

  private func store(_ results: [WebSearchResult], key: String) {
    cachedResults[key] = (results, Date().timeIntervalSince1970)
    resultOrder.removeAll { $0 == key }
    resultOrder.append(key)
    while resultOrder.count > SearchTuning.cacheCapacity, let oldest = resultOrder.first {
      resultOrder.removeFirst()
      cachedResults[oldest] = nil
    }
  }

  private func storeGuess(_ candidate: SearchCandidate, token: String) {
    cachedGuesses[token] = candidate
    guessOrder.removeAll { $0 == token }
    guessOrder.append(token)
    while guessOrder.count > SearchTuning.cacheCapacity, let oldest = guessOrder.first {
      guessOrder.removeFirst()
      cachedGuesses[oldest] = nil
    }
  }

  static func recency(_ lastVisit: Double, now: Double) -> Double {
    guard lastVisit > 0, now >= lastVisit else { return 0 }
    let days = (now - lastVisit) / 86_400
    guard days < SearchTuning.recencyHalfLifeDays * 8 else { return 0 }
    return pow(0.5, days / SearchTuning.recencyHalfLifeDays)
  }

  static func googleFallback(_ query: String) -> SearchCandidate? {
    guard var components = URLComponents(string: "https://www.google.com/search") else { return nil }
    components.queryItems = [URLQueryItem(name: "q", value: query)]
    guard let url = components.url else { return nil }
    return SearchCandidate(
      id: "google", kind: .google, title: "Search Google for “\(query)”", subtitle: "google.com",
      url: url, relevance: 0, confidence: 0, score: 0.5)
  }

  static func positionFallback(_ index: Int) -> Double {
    max(0, 1 - Double(index) * 0.06)
  }

  static func kind(_ value: LocalSignal.Kind) -> SearchCandidateKind {
    switch value {
    case .history: return .history
    case .bookmark: return .bookmark
    case .openTab: return .openTab
    case .shortcut: return .completion
    }
  }

  static func localCandidate(
    _ signal: LocalSignal, index: Int, relevance: Double, now: Double
  ) -> SearchCandidate {
    let score =
      SearchTuning.localTierBonus + relevance * SearchTuning.relevanceWeight
      + recency(signal.lastVisit, now: now) * SearchTuning.recencyWeight
      + min(Double(signal.visits), SearchTuning.visitCeiling) * SearchTuning.visitWeight
    let reason: String
    switch signal.kind {
    case .history: reason = "Visited"
    case .bookmark: reason = "Bookmarked"
    case .openTab: reason = "Open tab"
    case .shortcut: reason = "Shortcut"
    }
    return SearchCandidate(
      id: "local:\(index):\(signal.host)", kind: kind(signal.kind),
      title: signal.title.isEmpty ? signal.host : signal.title,
      subtitle: signal.host.isEmpty ? reason : "\(reason) · \(signal.host)", url: signal.url,
      relevance: relevance, confidence: relevance, score: score)
  }

  static func webCandidate(
    _ result: WebSearchResult, index: Int, url: URL, relevance: Double
  ) -> SearchCandidate {
    let score = SearchTuning.webTierBonus + relevance * SearchTuning.relevanceWeight
    return SearchCandidate(
      id: "web:\(index):\(result.host)", kind: .web,
      title: result.title.isEmpty ? result.host : result.title,
      subtitle: result.snippet.isEmpty ? result.host : result.snippet, url: url,
      relevance: relevance, confidence: relevance, score: score)
  }

  static func ordered(_ candidates: [SearchCandidate]) -> [SearchCandidate] {
    var seen = Set<String>()
    var kept: [SearchCandidate] = []
    for candidate in candidates.sorted(by: {
      $0.score == $1.score ? $0.title.count < $1.title.count : $0.score > $1.score
    }) {
      guard candidate.score > 0.4 else { continue }
      let key = candidate.url?.absoluteString ?? candidate.title
      guard seen.insert(key).inserted else { continue }
      kept.append(candidate)
    }
    return kept
  }
}
