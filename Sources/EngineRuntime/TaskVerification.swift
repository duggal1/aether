import BrowserEvents
import BrowserVerification
import EngineCore
import Foundation

extension BrowserRuntime {
  public func verify(
    _ plan: BrowserVerificationPlan,
    using externalVerifiers: [any BrowserExternalVerifier] = []
  ) async throws -> BrowserVerificationResult {
    try plan.validate()
    try Task.checkCancellation()

    var verifiers: [String: any BrowserExternalVerifier] = [:]
    for verifier in externalVerifiers {
      guard verifiers[verifier.identifier] == nil else {
        throw BrowserVerificationInputError.duplicateVerifier(verifier.identifier)
      }
      verifiers[verifier.identifier] = verifier
    }

    let page = try await synchronizedWebInfo(plan.pageID)
    var evidence: [BrowserVerificationEvidence] = []
    evidence.reserveCapacity(plan.checks.count)
    for check in plan.checks {
      try Task.checkCancellation()
      evidence.append(try await verify(check, page: page, verifiers: verifiers))
    }
    let status = Self.verificationStatus(for: evidence)
    return BrowserVerificationResult(
      status: status, pageID: page.id, contextID: page.contextID,
      checkedAt: Date(), evidence: evidence)
  }

  private func verify(
    _ check: BrowserVerificationCheck,
    page: BrowserPageInfo,
    verifiers: [String: any BrowserExternalVerifier]
  ) async throws -> BrowserVerificationEvidence {
    switch check.assertion {
    case .pageURL(let expectation):
      guard page.loaded, let url = page.url?.absoluteString else {
        return evidence(check, .inconclusive, "page", "Page URL is not available yet.")
      }
      let matched = expectation.mode.matches(url, expected: expectation.value)
      return evidence(
        check, matched ? .verified : .failed, "page.url",
        matched ? "Page URL matched the expectation." : "Page URL did not match the expectation.")

    case .pageTitle(let expectation):
      guard page.loaded else {
        return evidence(check, .inconclusive, "page", "Page title is not available yet.")
      }
      let matched = expectation.mode.matches(page.title, expected: expectation.value)
      return evidence(
        check, matched ? .verified : .failed, "page.title",
        matched ? "Page title matched the expectation." : "Page title did not match the expectation.")

    case .element(let selector, let condition):
      do {
        let nodes = try await queryAll(pageID: page.id, selector: selector)
        let matched = Self.elementCondition(condition, matches: nodes)
        let state = "Selector matched \(nodes.count) element(s)."
        return evidence(
          check, matched ? .verified : .failed, "page.dom",
          state + (matched ? " Expected state was present." : " Expected state was absent."))
      } catch {
        return evidence(check, .inconclusive, "page.dom", "Selector state could not be observed.")
      }

    case .navigationResponse(let expectation, let expectedStatusCode, let sinceSequence):
      let filter = BrowserEventBus.Filter(contexts: [page.contextID], pages: [page.id])
      let events = await recentEvents(limit: 2_048, filter: filter, since: sinceSequence)
      let observed = events.reversed().compactMap { event -> (String, Int)? in
        guard case .networkNavigationResponse(let url, let statusCode, _) = event.kind,
          expectation.mode.matches(url, expected: expectation.value)
        else { return nil }
        return (url, statusCode)
      }.first
      guard let (_, statusCode) = observed else {
        return evidence(
          check, .inconclusive, "webkit.mainFrameResponse",
          "No observable main-frame response matched the URL expectation.")
      }
      let matched = expectedStatusCode.map { $0 == statusCode } ?? true
      return evidence(
        check, matched ? .verified : .failed, "webkit.mainFrameResponse",
        "Observed main-frame response status \(statusCode)." +
          (matched ? " Status matched." : " Status did not match."))

    case .download(
      let expectation, let minimumBytes, let verifyFileExists, let downloadID, let sinceSequence):
      if let downloadID {
        do {
          let downloads = try listDownloads(contextID: page.contextID)
          guard let download = downloads.first(where: {
            $0.id.rawValue == downloadID &&
              expectation.mode.matches($0.url, expected: expectation.value)
          }) else {
            return evidence(check, .inconclusive, "download.metadata", "No matching download record exists.")
          }
          return downloadRecordEvidence(
            check, download: download, minimumBytes: minimumBytes,
            verifyFileExists: verifyFileExists)
        } catch {
          return evidence(check, .inconclusive, "download.metadata", "Download state could not be read.")
        }
      }

      let filter = BrowserEventBus.Filter(contexts: [page.contextID], pages: [page.id])
      let events = await recentEvents(
        limit: 2_048, filter: filter, since: sinceSequence ?? 0)
      for event in events.reversed() {
        switch event.kind {
        case .downloadFinished(let url, let path)
          where expectation.mode.matches(url, expected: expectation.value):
          return downloadEventEvidence(
            check, path: path, minimumBytes: minimumBytes,
            verifyFileExists: verifyFileExists)
        case .downloadFailed(let url, _)
          where expectation.mode.matches(url, expected: expectation.value):
          return evidence(check, .failed, "webkit.download", "The matching download failed.")
        default:
          continue
        }
      }
      return evidence(check, .inconclusive, "webkit.download", "No completed matching download was observed.")

    case .external(let identifier, let payload):
      guard let verifier = verifiers[identifier] else {
        return evidence(
          check, .inconclusive, "external.\(identifier)",
          "No external verifier is registered for this check.")
      }
      do {
        let result = try await verifier.verify(payload: payload)
        return evidence(
          check, result.status, "external.\(identifier)",
          String(result.summary.prefix(2_048)))
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        return evidence(
          check, .inconclusive, "external.\(identifier)",
          "External verifier did not return a result.")
      }
    }
  }

  private func downloadRecordEvidence(
    _ check: BrowserVerificationCheck,
    download: AgentDownloadInfo,
    minimumBytes: Int,
    verifyFileExists: Bool
  ) -> BrowserVerificationEvidence {
    guard download.state == "completed" else {
      if download.state == "failed" {
        return evidence(check, .failed, "download.metadata", "The matching download failed.")
      }
      return evidence(check, .inconclusive, "download.metadata", "The matching download is not complete.")
    }
    guard download.bytes >= minimumBytes else {
      return evidence(check, .failed, "download.metadata", "Download size was below the required minimum.")
    }
    return artifactEvidence(
      check, path: download.path, recordedBytes: download.bytes, minimumBytes: minimumBytes,
      verifyFileExists: verifyFileExists, source: "download.artifact")
  }

  private func downloadEventEvidence(
    _ check: BrowserVerificationCheck,
    path: String?,
    minimumBytes: Int,
    verifyFileExists: Bool
  ) -> BrowserVerificationEvidence {
    artifactEvidence(
      check, path: path, recordedBytes: nil, minimumBytes: minimumBytes,
      verifyFileExists: verifyFileExists, source: "webkit.download")
  }

  private func artifactEvidence(
    _ check: BrowserVerificationCheck,
    path: String?,
    recordedBytes: Int?,
    minimumBytes: Int,
    verifyFileExists: Bool,
    source: String
  ) -> BrowserVerificationEvidence {
    let needsFileSize = minimumBytes > 0
    guard verifyFileExists || needsFileSize else {
      return evidence(check, .verified, source, "Completed download satisfied the artifact requirements.")
    }
    guard let path else {
      if verifyFileExists {
        return evidence(check, .inconclusive, source, "Download path is unavailable.")
      }
      if let recordedBytes, recordedBytes >= minimumBytes {
        return evidence(check, .verified, source, "Download metadata met the minimum byte requirement.")
      }
      return evidence(check, .inconclusive, source, "Artifact size could not be verified.")
    }
    guard FileManager.default.fileExists(atPath: path) else {
      if let recordedBytes, recordedBytes >= minimumBytes, !verifyFileExists {
        return evidence(check, .verified, source, "Download metadata met the minimum byte requirement.")
      }
      return evidence(
        check, verifyFileExists ? .failed : .inconclusive, source,
        verifyFileExists ? "Downloaded artifact is missing." : "Artifact size could not be verified.")
    }
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: path)
      guard let size = (attributes[.size] as? NSNumber)?.intValue else {
        return evidence(check, .inconclusive, source, "Artifact size is unavailable.")
      }
      guard size >= minimumBytes else {
        return evidence(check, .failed, source, "Artifact size was below the required minimum.")
      }
      return evidence(check, .verified, source, "Completed download satisfied the artifact requirements.")
    } catch {
      return evidence(check, .inconclusive, source, "Artifact metadata could not be read.")
    }
  }

  private func evidence(
    _ check: BrowserVerificationCheck,
    _ status: BrowserVerificationStatus,
    _ source: String,
    _ summary: String
  ) -> BrowserVerificationEvidence {
    BrowserVerificationEvidence(
      checkID: check.id, status: status, source: source, summary: summary)
  }

  private static func elementCondition(
    _ condition: BrowserElementCondition,
    matches nodes: [InspectedNode]
  ) -> Bool {
    switch condition {
    case .exists: !nodes.isEmpty
    case .absent: nodes.isEmpty
    case .visible: nodes.contains(where: \.visible)
    case .enabled: nodes.contains(where: \.enabled)
    case .accessibleName(let expectation):
      nodes.contains { expectation.mode.matches($0.name, expected: expectation.value) }
    }
  }

  private static func verificationStatus(
    for evidence: [BrowserVerificationEvidence]
  ) -> BrowserVerificationStatus {
    if evidence.contains(where: { $0.status == .failed }) { return .failed }
    if evidence.contains(where: { $0.status == .inconclusive }) { return .inconclusive }
    return .verified
  }
}
