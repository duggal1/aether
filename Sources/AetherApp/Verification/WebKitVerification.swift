import AetherHumanUI
import AppKit
import EngineCore
import EngineRuntime
import Foundation

@MainActor
final class WebKitVerification {
  private var started = false

  struct Result: Codable {
    var requestedURL: String
    var finalURL: String?
    var title: String?
    var elapsedMilliseconds: Double
    var titleMilliseconds: Double?
    var details: String?
    var screenshot: String?
    var error: String?
  }

  struct StepResult: Codable {
    var flow: Int
    var step: Int
    var action: String
    var elapsedMilliseconds: Double
    var tabState: String
    var tabURL: String?
    var tabTitle: String?
    var contentReady: Bool
    var isLoading: Bool
    var engineURL: String?
    var engineTitle: String?
    var documentTitle: String?
    var bodyLength: Int?
    var readyState: String?
    var firstPaintMilliseconds: Int?
    var screenshot: String?
    var error: String?
  }

  func run(adapter: AetherEngineAdapter, workspace: BrowserWorkspace) async {
    guard !started, let window = workspace.windows.first else { return }
    started = true
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Aether/WebKitVerification", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if let sequence = ProcessInfo.processInfo.environment["AETHER_VERIFY_SEQUENCE"],
        !sequence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        try await runSequence(sequence, adapter: adapter, window: window, directory: directory)
        try Data("complete".utf8).write(to: directory.appendingPathComponent("complete"))
        return
      }
      let sites: [String]
      if let custom = ProcessInfo.processInfo.environment["AETHER_VERIFY_SITES"], !custom.isEmpty {
        sites = custom.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
      } else {
        sites = ["https://www.apple.com", "https://www.youtube.com", "https://en.wikipedia.org/wiki/WebKit", "http://localhost:8765/"]
      }
      var results: [Result] = []
      for (index, site) in sites.enumerated() {
        let start = Date()
        var result = Result(requestedURL: site, elapsedMilliseconds: 0)
        let tab = window.newTab(url: site)
        do {
          let clock = ContinuousClock()
          let deadline = clock.now.advanced(by: .seconds(65))
          var ready: String?
          while clock.now < deadline {
            try await Task.sleep(for: .milliseconds(200))
            if case .failed(let message) = tab.loadState { throw BrowserRuntimeError.invalidState(message) }
            if let page = tab.enginePageID {
              let state = try await adapter.snapshot(pageID: page)
              if result.titleMilliseconds == nil, !(state.title.isEmpty) {
                result.titleMilliseconds = Date().timeIntervalSince(start) * 1000
                ready = page
                break
              }
            }
          }
          guard let page = ready ?? tab.enginePageID else {
            throw BrowserRuntimeError.timeout("Page never started loading")
          }
          let id = try adapter.page(page)
          let state = try await adapter.snapshot(pageID: page)
          result.finalURL = state.url
          result.title = state.title
          if ProcessInfo.processInfo.environment["AETHER_VERIFY_PROOF"] != nil {
            result.details = try await adapter.engine.evaluate(pageID: id, source: """
            JSON.stringify({readyState:document.readyState,title:document.title,url:location.href,
              textLength:document.body.innerText.length,elements:document.querySelectorAll('*').length,
              images:Array.from(document.images).filter(i=>i.complete&&i.naturalWidth>0).length,
              viewport:[innerWidth,innerHeight],userAgent:navigator.userAgent,
              fixture:document.querySelector('#status')?.textContent ?? null,
              navigation:performance.getEntriesByType('navigation').map(n=>({responseEnd:n.responseEnd,domContentLoaded:n.domContentLoadedEventEnd,load:n.loadEventEnd}))})
            """).value
            let filename = "\(index + 1)-\(URL(string: site)?.host ?? "page").png"
            try await adapter.engine.render(pageID: id).write(to: directory.appendingPathComponent(filename))
            result.screenshot = filename
            if site.hasPrefix("http://localhost") {
              try await checkLocalPage(adapter: adapter, id: id)
            }
          }
        } catch { result.error = String(describing: error) }
        result.elapsedMilliseconds = Date().timeIntervalSince(start) * 1000
        results.append(result)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: directory.appendingPathComponent("results.json"), options: .atomic)
      }
      if let apple = window.tabs.first(where: { $0.url?.contains("apple.com") == true }) { window.select(apple.id) }
      try Data("complete".utf8).write(to: directory.appendingPathComponent("complete"))
    } catch {
      FileHandle.standardError.write(Data("WebKit verification: \(error)\n".utf8))
    }
  }

  private func runSequence(
    _ sequence: String, adapter: AetherEngineAdapter, window: BrowserWindowModel,
    directory: URL
  ) async throws {
    let flows = sequence.split(separator: ";").map {
      $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }.filter { !$0.isEmpty }
    var steps: [StepResult] = []
    func save() throws {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(steps).write(
        to: directory.appendingPathComponent("results-sequence.json"), options: .atomic)
    }
    for (flowIndex, flow) in flows.enumerated() {
      guard let first = flow.first, first.hasPrefix("go:") else { continue }
      let tab = window.newTab(url: String(first.dropFirst(3)))
      for (stepIndex, action) in flow.enumerated() {
        let start = Date()
        var result = StepResult(flow: flowIndex, step: stepIndex, action: action,
          elapsedMilliseconds: 0, tabState: "", tabURL: tab.url, tabTitle: tab.title,
          contentReady: tab.contentReady, isLoading: tab.isLoading,
          engineURL: nil, engineTitle: nil, documentTitle: nil, bodyLength: nil,
          readyState: nil, firstPaintMilliseconds: nil, screenshot: nil, error: nil)
        do {
          if stepIndex > 0 {
            if action.hasPrefix("go:") {
              window.navigate(tab, text: String(action.dropFirst(3)))
            } else if action == "back" {
              window.perform(.back)
            } else if action == "forward" {
              window.perform(.forward)
            } else if action == "reload" {
              window.perform(.reload)
            } else if action.hasPrefix("click:") {
              try await clickLink(String(action.dropFirst(6)), adapter: adapter, tab: tab)
            } else {
              throw BrowserRuntimeError.invalidNavigation("Unknown sequence action \(action)")
            }
          }
          try await settle(tab: tab, adapter: adapter)
          await fillStep(&result, tab: tab, adapter: adapter)
          if ProcessInfo.processInfo.environment["AETHER_VERIFY_PROOF"] != nil,
            let pageID = tab.enginePageID
          {
            let id = try adapter.page(pageID)
            let proof = try await adapter.engine.evaluate(pageID: id, source: """
              JSON.stringify({title:document.title,url:location.href,
                textLength:document.body ? document.body.innerText.length : -1,
                readyState:document.readyState,
                fcp:(performance.getEntriesByType('paint').find(p=>p.name==='first-contentful-paint')||{}).startTime ?? null})
              """).value
            if let data = proof.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
              result.documentTitle = dict["title"] as? String
              result.bodyLength = dict["textLength"] as? Int
              result.readyState = dict["readyState"] as? String
              if let fcp = dict["fcp"] as? Double { result.firstPaintMilliseconds = Int(fcp) }
            }
            let filename = "flow\(flowIndex)-step\(stepIndex).png"
            try await adapter.engine.render(pageID: id).write(
              to: directory.appendingPathComponent(filename))
            result.screenshot = filename
          }
        } catch {
          result.error = String(describing: error)
          await fillStep(&result, tab: tab, adapter: adapter)
        }
        result.elapsedMilliseconds = Date().timeIntervalSince(start) * 1000
        result.tabState = describeLoadState(tab.loadState)
        result.tabURL = tab.url
        result.tabTitle = tab.title
        result.contentReady = tab.contentReady
        result.isLoading = tab.isLoading
        steps.append(result)
        try save()
      }
    }
  }

  private func describeLoadState(_ state: TabLoadState) -> String {
    switch state {
    case .newTab: return "newTab"
    case .loading: return "loading"
    case .ready: return "ready"
    case .search(let query): return "search(\(query))"
    case .failed(let message): return "failed(\(message.prefix(120)))"
    }
  }

  private func fillStep(_ result: inout StepResult, tab: BrowserTab, adapter: AetherEngineAdapter) async {
    result.tabState = describeLoadState(tab.loadState)
    result.tabURL = tab.url
    result.tabTitle = tab.title
    result.contentReady = tab.contentReady
    result.isLoading = tab.isLoading
    if let pageID = tab.enginePageID, let state = try? await adapter.snapshot(pageID: pageID) {
      result.engineURL = state.url
      result.engineTitle = state.title
    }
  }

  private func settle(tab: BrowserTab, adapter: AetherEngineAdapter) async throws {
    let deadline = Date().addingTimeInterval(45)
    while Date() < deadline {
      switch tab.loadState {
      case .ready: return
      case .failed(let message): throw BrowserRuntimeError.invalidState(message)
      case .search(let query): throw BrowserRuntimeError.invalidState("Unexpected search: \(query)")
      case .newTab, .loading: break
      }
      try await Task.sleep(for: .milliseconds(200))
    }
    throw BrowserRuntimeError.timeout(
      "Tab did not settle: \(describeLoadState(tab.loadState)) url=\(tab.url ?? "nil")")
  }

  private func clickLink(_ text: String, adapter: AetherEngineAdapter, tab: BrowserTab) async throws {
    guard let pageID = tab.enginePageID else { throw BrowserPortError.pageUnavailable }
    let id = try adapter.page(pageID)
    let before = tab.url
    let nodes = try await adapter.engine.runtime.queryAll(pageID: id, selector: "a")
    guard let link = nodes.first(where: { $0.name.localizedCaseInsensitiveContains(text) })
    else { throw BrowserRuntimeError.invalidState("No link containing \(text)") }
    _ = try await adapter.engine.runtime.click(pageID: id, nodeID: link.id)
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline {
      if let current = tab.url, current != before, tab.loadState != .loading { return }
      if case .failed(let message) = tab.loadState {
        throw BrowserRuntimeError.invalidState(message)
      }
      try await Task.sleep(for: .milliseconds(250))
    }
    throw BrowserRuntimeError.timeout("Link click did not navigate away from \(before ?? "nil")")
  }

  private func checkLocalPage(adapter: AetherEngineAdapter, id: PageID) async throws {
    let runtime = adapter.engine.runtime
    guard let input = try await runtime.query(pageID: id, selector: "#name"),
      let button = try await runtime.query(pageID: id, selector: "#apply") else {
      throw BrowserRuntimeError.invalidState("Local dynamic fixture controls are missing")
    }
    try await runtime.fill(pageID: id, nodeID: input.id, value: "Aether WebKit")
    _ = try await runtime.click(pageID: id, nodeID: button.id)
    let value = try await runtime.evaluate(pageID: id, source: "document.querySelector('#result').textContent")
    guard value.value == "Hello Aether WebKit" else {
      throw BrowserRuntimeError.invalidState("Live DOM input/click failed: \(value.value)")
    }
    _ = try await runtime.evaluate(pageID: id, source: "localStorage.setItem('aether-check','persisted'); location.hash='verified'; 'ok'")
    _ = try await runtime.reload(pageID: id)
    let storage = try await runtime.evaluate(pageID: id, source: "localStorage.getItem('aether-check')")
    guard storage.value == "persisted" else { throw BrowserRuntimeError.invalidState("Storage did not survive reload") }
    let state = try await runtime.snapshot(pageID: id)
    guard !state.nodes.isEmpty else { throw BrowserRuntimeError.invalidState("Live DOM snapshot is empty") }
    do {
      _ = try await runtime.click(pageID: id, nodeID: button.id)
      throw BrowserRuntimeError.invalidState("A stale node ID was accepted after reload")
    } catch BrowserRuntimeError.nodeNotFound { }
  }
}
