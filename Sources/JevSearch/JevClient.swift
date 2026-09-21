import Foundation

public actor JevClient {
  private nonisolated let configuration: JevConfiguration
  private let transport: any HTTPPostTransport

  public init(configuration: JevConfiguration, transport: any HTTPPostTransport = URLSessionTransport()) {
    self.configuration = configuration
    self.transport = transport
  }

  public nonisolated var isConfigured: Bool { configuration.hasIntelligence }

  public func ask<S: Encodable & Sendable>(state: S, questions: [String: JevQuestion]) async throws
    -> JevResponse
  {
    guard configuration.hasIntelligence else { throw JevError.notConfigured }
    let encoder = JSONEncoder()
    let stateObject = try JSONSerialization.jsonObject(with: try encoder.encode(state))
    let questionObject = try JSONSerialization.jsonObject(with: try encoder.encode(questions))
    let root: [String: Any] = [
      "model": configuration.model, "state": stateObject, "questions": questionObject,
    ]
    let body = try JSONSerialization.data(withJSONObject: root)
    let data = try await transport.post(
      body, to: configuration.typeSafeEndpoint, bearer: configuration.typeSafeKey,
      timeout: configuration.timeout)
    do {
      return try JSONDecoder().decode(JevResponse.self, from: data)
    } catch {
      throw JevError.decoding("\(error)")
    }
  }
}
