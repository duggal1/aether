import ContentBlocker
import Foundation
import Testing

@Test func configuredFiltersRespectSiteExceptions() throws {
  let filter = FilterEngine()
  try filter.replaceRules(from: "||tracker.example^\n@@||tracker.example/allowed^")
  #expect(filter.decide(url: URL(string: "https://tracker.example/pixel")!, kind: .image,
    documentURL: URL(string: "https://site.example")!).blocked)
  #expect(!filter.decide(url: URL(string: "https://tracker.example/allowed/")!, kind: .image,
    documentURL: URL(string: "https://site.example")!).blocked)
}
