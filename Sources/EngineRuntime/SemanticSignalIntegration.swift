import DOM
import EngineCore
import Foundation
import JevSearch

extension BrowserRuntime {
  func scheduleSemanticAnalysis(_ state: RuntimePageState) {
    let pageID = state.page.id
    guard !state.closed else {
      discardSemanticState(for: pageID)
      return
    }

    let target = state.target ?? state.page.url
    let targetKey = target?.absoluteString
    if semanticTargetURLs[pageID] != targetKey {
      semanticAnalysisTasks.removeValue(forKey: pageID)?.cancel()
      semanticScheduledRevisions[pageID] = nil
      semanticObservationsByPage[pageID] = nil
      semanticPageAssessmentTargets[pageID] = nil
      semanticSignalsByPage[pageID] = nil
      semanticTargetURLs[pageID] = targetKey
    }

    guard let context = contexts[state.page.contextID] else { return }
    if webEphemeral.contains(context.id) {
      if semanticSignalsByPage[pageID] != nil || semanticObservationsByPage[pageID] != nil
        || semanticImportanceCache[pageID] != nil {
        discardSemanticState(for: pageID)
      }
      return
    }
    guard state.contentReady, !state.loading, let target, Self.isClassifiablePage(target),
      semanticScheduledRevisions[pageID] != state.semanticRevision else { return }

    semanticScheduledRevisions[pageID] = state.semanticRevision
    semanticAnalysisTasks.removeValue(forKey: pageID)?.cancel()
    semanticAnalysisTasks[pageID] = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(450))
      guard !Task.isCancelled else { return }
      await self?.analyzeSemanticPage(
        pageID: pageID, target: target, revision: state.semanticRevision)
    }
  }

  func discardSemanticState(for pageID: PageID) {
    semanticAnalysisTasks.removeValue(forKey: pageID)?.cancel()
    semanticScheduledRevisions[pageID] = nil
    semanticTargetURLs[pageID] = nil
    semanticObservationsByPage[pageID] = nil
    semanticPageAssessmentTargets[pageID] = nil
    semanticSignalsByPage[pageID] = nil
    semanticImportanceCache[pageID] = nil
  }

  func classifyFileUpload(pageID: PageID, context: SemanticUploadContext) async {
    guard let ownerID = contextID(containing: pageID),
      !webEphemeral.contains(ownerID),
      let before = webStates[pageID]?.url?.absoluteString else { return }
    guard let result = await semanticSignalService.classifyFileUpload(context) else { return }
    guard !Task.isCancelled,
      contextID(containing: pageID) == ownerID,
      webStates[pageID]?.url?.absoluteString == before else { return }

    var signals = semanticSignalsByPage[pageID] ?? SemanticPageSignals()
    signals.uploadIntent = result.intent
    signals.uploadConfidence = result.confidence
    semanticSignalsByPage[pageID] = signals
    publishPageState(pageID)
  }

  public func joinMeeting(pageID: PageID) async {
    guard let ownerID = contextID(containing: pageID),
      !webEphemeral.contains(ownerID), let page = webPages[pageID],
      let url = webStates[pageID]?.url, let host = url.host else { return }
    do {
      let controls = try await page.query("button, a, [role=button]")
        .filter { $0.visible && $0.enabled && !$0.name.isEmpty }
        .prefix(24)
      guard !controls.isEmpty else { return }
      let candidates = controls.enumerated().map { index, node in
        SemanticActionCandidate(
          id: "action_\(index)", role: String(node.role.prefix(40)),
          label: String(node.name.prefix(140)))
      }
      let excerpt = (try? await page.script(
        "(document.querySelector('main') || document.body)?.innerText || ''")) ?? ""
      let selected = await semanticSignalService.selectMeetingJoinAction(
        host: String(host.prefix(160)), title: String((webStates[pageID]?.title ?? "").prefix(180)),
        visibleText: String(excerpt.prefix(1000)), candidates: candidates)
      guard let selected,
        let index = Int(selected.dropFirst("action_".count)), controls.indices.contains(index),
        contextID(containing: pageID) == ownerID, webPages[pageID] === page else { return }
      try await page.nodeAction(controls[index].id, body: """
        if (!n.isConnected || n.matches(':disabled') || n.getAttribute('aria-disabled') === 'true') {
          throw new Error('Meeting action is no longer available');
        }
        const rect = n.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0) throw new Error('Meeting action is not visible');
        n.scrollIntoView({block:'center'}); n.focus(); n.click();
        """)
    } catch {
      return
    }
  }

  private func analyzeSemanticPage(pageID: PageID, target: URL, revision: UInt64) async {
    guard await semanticSignalService.isConfigured else {
      semanticScheduledRevisions[pageID] = nil
      return
    }
    guard let page = webPages[pageID], let contextID = contextID(containing: pageID),
      !webEphemeral.contains(contextID), let context = contexts[contextID],
      let record = context.pages[pageID] else { return }
    let currentState = state(for: record)
    guard currentState.contentReady, !currentState.loading,
      currentState.semanticRevision == revision,
      (currentState.target ?? currentState.page.url) == target else { return }

    let observation: SemanticPageObservation
    do {
      try? await page.startSemanticObservation()
      let snapshot = try await page.snapshot(info: currentState.page, limit: 1800)
      observation = makeSemanticObservation(snapshot, contextID: contextID)
    } catch {
      return
    }
    guard !Task.isCancelled,
      let latest = contexts[contextID]?.pages[pageID],
      state(for: latest).semanticRevision == revision,
      (state(for: latest).target ?? state(for: latest).page.url) == target else { return }

    let previous = semanticObservationsByPage[pageID]
    guard previous != observation else { return }
    semanticObservationsByPage[pageID] = observation

    let overlayOnlyChange = previous.map {
      Self.withoutOverlays($0) == Self.withoutOverlays(observation)
    } ?? false
    if overlayOnlyChange, semanticPageAssessmentTargets[pageID] == target.absoluteString {
      guard let candidate = observation.overlays.first else {
        if var signals = semanticSignalsByPage[pageID] {
          signals.overlay = nil
          semanticSignalsByPage[pageID] = signals
          publishPageState(pageID)
        }
        return
      }
      if var signals = semanticSignalsByPage[pageID] {
        signals.overlay = nil
        semanticSignalsByPage[pageID] = signals
      }
      publishPageState(pageID)
      guard let overlay = await semanticSignalService.assessOverlay(
        observation: observation, candidate: candidate), !Task.isCancelled,
        semanticObservationsByPage[pageID] == observation else { return }
      var signals = semanticSignalsByPage[pageID] ?? SemanticPageSignals()
      signals.overlay = overlay
      semanticSignalsByPage[pageID] = signals
      publishPageState(pageID)
      return
    }

    semanticPageAssessmentTargets[pageID] = nil
    semanticSignalsByPage[pageID] = nil
    publishPageState(pageID)
    guard var signals = await semanticSignalService.assessPage(observation),
      !Task.isCancelled, semanticObservationsByPage[pageID] == observation,
      let latestRecord = contexts[contextID]?.pages[pageID],
      state(for: latestRecord).semanticRevision == revision else { return }
    semanticPageAssessmentTargets[pageID] = target.absoluteString

    if let relatedID = signals.relatedPageID, let rawID = UInt64(relatedID) {
      let relatedPageID = PageID(rawValue: rawID)
      guard contexts[contextID]?.pages[relatedPageID] != nil else {
        signals.semanticGroupID = pageID.description
        semanticSignalsByPage[pageID] = signals
        publishPageState(pageID)
        return
      }
      let relatedSignals = semanticSignalsByPage[relatedPageID]
      let groupID = relatedSignals?.semanticGroupID ?? relatedID
      signals.semanticGroupID = groupID
      if let relatedSignals {
        var updatedRelatedSignals = relatedSignals
        updatedRelatedSignals.semanticGroupID = groupID
        semanticSignalsByPage[relatedPageID] = updatedRelatedSignals
        publishPageState(relatedPageID)
      }
    } else {
      signals.semanticGroupID = pageID.description
    }
    semanticSignalsByPage[pageID] = signals
    publishPageState(pageID)
  }

  private func makeSemanticObservation(
    _ snapshot: PageSnapshot, contextID: ContextID
  ) -> SemanticPageObservation {
    let nodes = snapshot.nodes
    let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    let editableIDs = Set(nodes.filter(\.editable).map(\.id))
    func belongsToEditableContent(_ node: PageNodeSnapshot) -> Bool {
      var parent = node.parent
      while let id = parent, let ancestor = nodeByID[id] {
        if editableIDs.contains(id) { return true }
        parent = ancestor.parent
      }
      return false
    }
    let visibleText = Self.compact(nodes.lazy.filter {
      $0.kind == "text" && $0.visible && !belongsToEditableContent($0)
    }.compactMap(\.text).joined(separator: " "), limit: 1800)
    let elements = nodes.lazy.filter { node in
      guard node.kind == "element", node.visible else { return false }
      let tag = node.tag?.lowercased() ?? ""
      let role = node.role?.lowercased() ?? ""
      return ["button", "a", "input", "textarea", "select"].contains(tag)
        || ["button", "link", "dialog"].contains(role)
    }.prefix(96).map { node in
      SemanticPageElement(
        role: String((node.role ?? "generic").prefix(40)),
        kind: String((node.tag ?? "element").prefix(24)),
        label: String((node.attributes["aria-label"] ?? node.name).prefix(140)),
        acceptedTypes: node.attributes["accept"].map { String($0.prefix(120)) })
    }
    let overlayRoots = nodes.filter { node in
      guard node.kind == "element", node.visible else { return false }
      let role = node.attributes["role"]?.lowercased()
      return role == "dialog" || node.attributes["aria-modal"]?.lowercased() == "true"
        || node.tag?.lowercased() == "dialog"
    }
    let primaryOverlay = overlayRoots.first {
      $0.attributes["aria-modal"]?.lowercased() == "true"
    } ?? overlayRoots.first { $0.attributes["role"]?.lowercased() == "dialog" }
      ?? overlayRoots.first
    let overlays: [SemanticOverlayCandidate] = primaryOverlay.map { node -> [SemanticOverlayCandidate] in
      let descendantText = nodes.lazy.filter {
        $0.visible && !belongsToEditableContent($0) && Self.isDescendant($0, of: node, in: nodeByID)
      }.compactMap { child in child.kind == "text" ? child.text : nil }.joined(separator: " ")
      return [SemanticOverlayCandidate(
        role: String((node.attributes["role"] ?? node.tag ?? "dialog").prefix(40)),
        label: String((node.attributes["aria-label"] ?? node.name).prefix(160)),
        text: Self.compact(descendantText, limit: 700))]
    } ?? []
    let host = snapshot.page.url?.host?.lowercased() ?? ""
    let peers = contexts[contextID]?.pages.values.compactMap { peer -> SemanticPeerPage? in
      guard peer.id != snapshot.page.id,
        let observation = semanticObservationsByPage[peer.id] else { return nil }
      return SemanticPeerPage(
        id: peer.id.description, title: String(observation.title.prefix(140)),
        host: String(observation.host.prefix(120)), excerpt: String(observation.visibleText.prefix(260)))
    }.prefix(24) ?? []
    return SemanticPageObservation(
      id: snapshot.page.id.description, host: String(host.prefix(160)),
      title: String(snapshot.page.title.prefix(180)), visibleText: visibleText,
      elements: Array(elements), overlays: Array(overlays), peerPages: Array(peers))
  }

  func hibernationProtection(for pageID: PageID) async -> Bool {
    guard let page = webPages[pageID],
      let result = try? await page.script("""
      (() => {
        const dirty = typeof window.__aetherHasDirtyForm === 'function'
          ? window.__aetherHasDirtyForm() : Boolean(window.__aetherHasDirtyForm);
        const playing = window.__aetherTabAudio?.hasActivePlayback?.() ||
          Array.from(document.querySelectorAll('audio,video')).some(media =>
            !media.paused && !media.ended && !media.muted && media.volume > 0);
        return Boolean(dirty || playing);
      })()
      """)
    else { return false }
    return result == "true"
  }

  func importanceInput(for page: PageRecord) -> SemanticTabImportanceInput {
    let observation = semanticObservationsByPage[page.id]
    let address = observation?.host ?? info(for: page).url?.host ?? ""
    return SemanticTabImportanceInput(
      id: page.id.description, title: String((observation?.title ?? info(for: page).title).prefix(180)),
      host: String(address.prefix(160)), excerpt: String((observation?.visibleText ?? "").prefix(400)))
  }

  private static func isClassifiablePage(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else { return false }
    return ["http", "https"].contains(scheme) && url.host != nil
  }

  private static func withoutOverlays(_ observation: SemanticPageObservation) -> SemanticPageObservation {
    SemanticPageObservation(
      id: observation.id, host: observation.host, title: observation.title,
      visibleText: observation.visibleText, elements: observation.elements, overlays: [],
      peerPages: observation.peerPages)
  }

  private static func isDescendant(
    _ node: PageNodeSnapshot, of ancestor: PageNodeSnapshot,
    in nodes: [NodeID: PageNodeSnapshot]
  ) -> Bool {
    var parent = node.parent
    while let id = parent, let value = nodes[id] {
      if value.id == ancestor.id { return true }
      parent = value.parent
    }
    return node.id == ancestor.id
  }

  private static func compact(_ text: String, limit: Int) -> String {
    let normalized = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return String(normalized.prefix(limit))
  }
}
