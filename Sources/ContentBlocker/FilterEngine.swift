import Foundation
import Synchronization

public final class FilterEngine: @unchecked Sendable {
  private struct State {
    var configuration = BlockerConfiguration()
    var networkRules: [NetworkFilterRule] = []
    var cosmeticRules: [CosmeticFilterRule] = []
    var stats = FilterStats()
    var cosmeticSiteHosts: Set<String> = []
    var lastUpdateError: String?
  }

  private let lock = Mutex(State())

  public init(configuration: BlockerConfiguration = BlockerConfiguration()) {
    lock.withLock { $0.configuration = configuration }
  }

  public func updateConfiguration(_ configuration: BlockerConfiguration) {
    lock.withLock { $0.configuration = configuration }
  }

  public func configuration() -> BlockerConfiguration {
    lock.withLock { $0.configuration }
  }

  public func replaceRules(from text: String) throws {
    let parsed = FilterListParser.parse(text)
    let state = lock.withLock { $0 }
    let previousCount = state.networkRules.count + state.cosmeticRules.count
    guard parsed.accepted > 0 || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      let error = BlockerError.emptyRuleSetRejected(previousRuleCount: previousCount)
      lock.withLock { $0.lastUpdateError = String(describing: error) }
      throw error
    }
    let total = parsed.network.count + parsed.cosmetic.count
    guard total <= state.configuration.maximumRules else {
      let error = BlockerError.ruleLimitExceeded(limit: state.configuration.maximumRules)
      lock.withLock { $0.lastUpdateError = String(describing: error) }
      throw error
    }
    lock.withLock {
      $0.networkRules = parsed.network
      $0.cosmeticRules = parsed.cosmetic
      $0.stats.networkRules = parsed.network.count
      $0.stats.cosmeticRules = parsed.cosmetic.count
      $0.cosmeticSiteHosts.removeAll()
      $0.lastUpdateError = parsed.skipped > 0 ? "\(parsed.skipped) filter lines skipped" : nil
    }
  }

  public func lastUpdateNotice() -> String? {
    lock.withLock { $0.lastUpdateError }
  }

  public func decide(url: URL, kind: BlockResourceKind, documentURL: URL?) -> BlockDecision {
    var outcome: BlockDecision?
    lock.withLock { state in
      guard state.configuration.enabled else {
        outcome = .allow
        return
      }
      state.stats.requestsEvaluated += 1
      let urlHost = url.host?.lowercased()
      let documentHost = documentURL?.host?.lowercased()
      if let documentHost, state.configuration.temporaryAllowedDomains.contains(documentHost) {
        state.stats.allowlistedRequests += 1
        outcome = .allow
        return
      }
      if let urlHost, state.configuration.temporaryAllowedDomains.contains(urlHost) {
        state.stats.allowlistedRequests += 1
        outcome = .allow
        return
      }
      var importantBlock: String?
      var blocking: String?
      var exceptionMatched = false
      for rule in state.networkRules {
        guard rule.matches(url: url, kind: kind, documentHost: documentHost) else { continue }
        if rule.isException {
          exceptionMatched = true
          continue
        }
        let reason = "content blocked by filter for \(url.absoluteString)"
        if rule.important { importantBlock = reason } else { blocking = blocking ?? reason }
      }
      if let reason = importantBlock {
        state.stats.requestsBlocked += 1
        outcome = .block(reason)
        return
      }
      if exceptionMatched {
        state.stats.exceptionsMatched += 1
        outcome = .allow
        return
      }
      if let reason = blocking {
        state.stats.requestsBlocked += 1
        outcome = .block(reason)
        return
      }
      outcome = .allow
    }
    return outcome ?? .allow
  }

  public func cosmeticSelectors(for documentURL: URL) -> [String] {
    var selectors: [String]?
    lock.withLock { state in
      guard state.configuration.enabled, !state.cosmeticRules.isEmpty else { return }
      let host = documentURL.host?.lowercased()
      let exceptions = Set(
        state.cosmeticRules.filter { $0.isException }.map { $0.selector })
      var matched: [String] = []
      matched.reserveCapacity(state.cosmeticRules.count)
      for rule in state.cosmeticRules where !rule.isException {
        guard !exceptions.contains(rule.selector), rule.applies(toHost: host) else { continue }
        matched.append(rule.selector)
        if matched.count >= 2000 { break }
      }
      guard !matched.isEmpty else { return }
      state.cosmeticSiteHosts.insert(host ?? "")
      state.stats.cosmeticSitesStyled = state.cosmeticSiteHosts.count
      selectors = matched
    }
    return selectors ?? []
  }

  public func temporaryAllow(host: String) throws {
    let normalized = host.lowercased()
    guard FilterListParser.isValidDomain(normalized) else {
      throw BlockerError.invalidDomain(normalized)
    }
    lock.withLock { $0.configuration.temporaryAllowedDomains.insert(normalized) }
  }

  public func removeTemporaryAllow(host: String) {
    lock.withLock { $0.configuration.temporaryAllowedDomains.remove(host.lowercased()) }
  }

  public func stats() -> FilterStats {
    lock.withLock { $0.stats }
  }

  public func resetStats() {
    lock.withLock { state in
      let rules = state.stats
      state.stats = FilterStats(
        networkRules: rules.networkRules, cosmeticRules: rules.cosmeticRules)
    }
  }
}
