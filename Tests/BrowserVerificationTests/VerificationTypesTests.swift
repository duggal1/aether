import BrowserVerification
import EngineCore
import Foundation
import Testing

@Test func verificationPlanUsesStableWireShapeAndRoundTrips() throws {
  let plan = BrowserVerificationPlan(
    pageID: PageID(rawValue: 42),
    checks: [
      BrowserVerificationCheck(
        id: "url",
        assertion: .pageURL(BrowserTextExpectation("https://example.test", mode: .prefix))),
      BrowserVerificationCheck(
        id: "submit",
        assertion: .element(
          selector: "button[type=submit]", condition: .accessibleName(.init("Submit")))),
      BrowserVerificationCheck(
        id: "external",
        assertion: .external(identifier: "deployment", payload: Data("{}".utf8))),
    ])
  let data = try JSONEncoder().encode(plan)
  let wire = try #require(
    JSONSerialization.jsonObject(with: data) as? [String: Any])
  #expect(wire["page"] as? Int == 42)
  #expect(wire["pageID"] == nil)
  let decoded = try JSONDecoder().decode(BrowserVerificationPlan.self, from: data)
  #expect(decoded == plan)
}

@Test func verificationPlanRejectsAmbiguousAndUnboundedInputs() {
  let duplicateIDs = BrowserVerificationPlan(
    pageID: PageID(rawValue: 1),
    checks: [
      BrowserVerificationCheck(id: "same", assertion: .pageTitle(.init("A"))),
      BrowserVerificationCheck(id: "same", assertion: .pageURL(.init("B"))),
    ])
  #expect(throws: BrowserVerificationInputError.self) {
    try duplicateIDs.validate()
  }

  let invalidDownload = BrowserVerificationPlan(
    pageID: PageID(rawValue: 1),
    checks: [
      BrowserVerificationCheck(
        id: "large", assertion: .download(
          url: .init("artifact.zip"), minimumBytes: Int.max, verifyFileExists: true,
          downloadID: nil, sinceSequence: 0))
    ])
  #expect(throws: BrowserVerificationInputError.self) {
    try invalidDownload.validate()
  }
}

@Test func textMatchModesHaveExplicitSemantics() {
  #expect(BrowserTextMatchMode.exact.matches("Aether", expected: "Aether"))
  #expect(!BrowserTextMatchMode.exact.matches("Aether", expected: "aether"))
  #expect(BrowserTextMatchMode.contains.matches("Deployment complete", expected: "COMPLETE"))
  #expect(BrowserTextMatchMode.prefix.matches("https://example.test/path", expected: "https://example.test"))
}
