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

  func run(adapter: AetherEngineAdapter, workspace: BrowserWorkspace) async {
    guard !started, let window = workspace.windows.first else { return }
    started = true
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Aether/WebKitVerification", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
