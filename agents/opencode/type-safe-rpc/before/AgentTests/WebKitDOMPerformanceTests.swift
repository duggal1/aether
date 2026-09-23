import EngineCore
import Foundation
import Testing
@testable import EngineRuntime

@MainActor
@Test func webKitDOMBatchingPreservesResultsAndMeasuresRoundTrips() async throws {
  let page = WebKitPage(context: WebKitContext.ephemeral(),
    viewport: Size(width: 1280, height: 800), changed: { _ in })
  defer { page.close() }
  try await page.loadHTML("<title>DOM benchmark</title><button id='target'>Target</button>",
    url: URL(string: "https://fixture.test/")!)
  let source = "JSON.stringify(Array.from(document.querySelectorAll('#target')).map(n => globalThis.__aetherDOM.describe(n)))"
  func separate() async throws -> [InspectedNode] {
    _ = try await page.script(WebKitDOMScript.source(generation: page.generation))
    return try await page.decode([WebDOMNode].self, source).map(\.inspected)
  }
  let clock = ContinuousClock()
  var separateTimes: [Duration] = []
  var batchedTimes: [Duration] = []
  for index in 0..<220 {
    let start = clock.now
    let first = try await (index.isMultiple(of: 2) ? separate() : page.query("#target"))
    let middle = clock.now
    let second = try await (index.isMultiple(of: 2) ? page.query("#target") : separate())
    let end = clock.now
    #expect(first == second)
    #expect(first.first?.name == "Target")
    if index >= 20 {
      separateTimes.append(index.isMultiple(of: 2) ? start.duration(to: middle) : middle.duration(to: end))
      batchedTimes.append(index.isMultiple(of: 2) ? middle.duration(to: end) : start.duration(to: middle))
    }
  }
  func medianMilliseconds(_ times: [Duration]) -> Double {
    let sorted = times.sorted()
    let median = (sorted[99] + sorted[100]) / 2
    return Double(median.components.seconds) * 1_000 + Double(median.components.attoseconds) / 1e15
  }
  print("WEBKIT_DOM_BENCH samples=200 separate_median_ms=\(medianMilliseconds(separateTimes)) batched_median_ms=\(medianMilliseconds(batchedTimes))")
}
