import AetherHumanUI
import BrowserEngine
import DOM
import EngineCore
import EngineRuntime
import Foundation

extension AetherEngineAdapter: BrowserInspectionProviding, BrowserReaderProviding,
  BrowserDownloadsProviding, BrowserFindProviding, BrowserSearchSuggesting {
  func searchCompletions(prefix: String, limit: Int, providerEndpoint: URL?) async throws
    -> [String]
  {
    guard !prefix.isEmpty else { return [] }
    return await engine.runtime.searchCompletions(
      prefix: prefix, limit: limit, endpoint: providerEndpoint)
  }

  func warmSearchCompletions(providerEndpoint: URL?) async {
    await engine.runtime.warmSearchSuggestions(endpoint: providerEndpoint)
  }

  func inspect(pageID: String) async throws -> BrowserInspectionSnapshot {
    let id = try page(pageID)
    let snapshot = try await engine.snapshot(pageID: id)
    let document = try await engine.runtime.captureDocument(pageID: id,
      includeComputedStyles: true, redactSensitive: true)
    let byID = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
    let nodes = snapshot.nodes.map { node in
      var depth = 0
      var parent = node.parent
      while let id = parent, let ancestor = byID[id], depth < 128 { depth += 1; parent = ancestor.parent }
      let summary = node.tag.map { "<\($0)> \(node.name)" } ?? node.text ?? node.kind
      return InspectionNode(id: node.id.description, depth: depth, summary: summary, html: summary)
    }
    return BrowserInspectionSnapshot(nodes: nodes, documentHTML: document.html,
      availableCSS: document.stylesheets.map(\.css).joined(separator: "\n\n"),
      consoleMessages: [],
      networkRequests: try await engine.runtime.networkLogEntries(pageID: id).map {
        "\($0.statusCode) \($0.url) — \($0.durationMilliseconds) ms"
      })
  }

  func highlight(nodeID: String, pageID: String) async throws {
    let parts = nodeID.split(separator: ":")
    guard parts.count == 2, let index = UInt32(parts[0]), let generation = UInt32(parts[1]) else {
      throw BrowserPortError.pageUnavailable
    }
    _ = try await engine.runtime.scrollIntoView(pageID: page(pageID),
      nodeID: NodeID(index: index, generation: generation))
  }

  func markdown(pageID: String) async throws -> String {
    let state = try await snapshot(pageID: pageID)
    let body = try await engine.runtime.webReaderMarkdown(pageID: page(pageID))
    guard !body.isEmpty else {
      return "# \(state.title)\n\n" + (try await engine.runtime.webDocumentText(pageID: page(pageID)))
    }
    return "# \(state.title)\n\n" + body
  }

  func downloads(profileID: UUID) async throws -> [BrowserDownloadRecord] {
    let context = try await context(for: profileID)
    return try await engine.runtime.listDownloads(contextID: context).map {
      BrowserDownloadRecord(id: $0.id.description,
        fileName: $0.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? URL(string: $0.url)?.lastPathComponent ?? "Download",
        bytesReceived: Int64($0.bytes), totalBytes: $0.state == "complete" ? Int64($0.bytes) : nil,
        isComplete: $0.state == "complete", localFileURL: $0.path.map { URL(fileURLWithPath: $0) })
    }
  }

  func cancelDownload(id: String, profileID: UUID) async throws {
    throw BrowserPortError.unsupported("download cancellation")
  }

  func find(pageID: String, query: String, forward: Bool) async throws -> Int {
    guard !query.isEmpty else { return 0 }
    return try await engine.runtime.findWebText(pageID: page(pageID), query: query, forward: forward)
  }
}

extension AetherEngineAdapter: BrowserSessionStateProviding {
  func sessionState(pageID: String) async -> EngineSessionState {
    guard let id = try? page(pageID) else { return .notLoaded }
    let state = await engine.runtime.sessionAuthState(pageID: id)
    return EngineSessionState(rawValue: state.rawValue) ?? .notLoaded
  }
}

extension AetherEngineAdapter: BrowserWebInspectorProviding {
  func toggleWebInspector(pageID: String) async throws {
    try await engine.runtime.toggleInspector(pageID: page(pageID))
  }

  func showWebConsole(pageID: String) async throws {
    try await engine.runtime.showConsole(pageID: page(pageID))
  }

  func pickWebElement(pageID: String) async throws {
    try await engine.runtime.inspectElement(pageID: page(pageID))
  }
}
