import Foundation

public enum AgentCodec {
  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private static let decoder = JSONDecoder()

  public static func encode(_ request: AgentRequest) throws -> Data {
    var data = try encoder.encode(request)
    data.append(0x0A)
    return data
  }

  public static func encode(_ response: AgentResponse) throws -> Data {
    var data = try encoder.encode(response)
    data.append(0x0A)
    return data
  }

  public static func decodeRequest(_ data: Data) throws -> AgentRequest {
    try decoder.decode(AgentRequest.self, from: trimmed(data))
  }

  public static func decodeResponse(_ data: Data) throws -> AgentResponse {
    try decoder.decode(AgentResponse.self, from: trimmed(data))
  }

  private static func trimmed(_ data: Data) -> Data {
    var value = data
    while value.last == 0x0A || value.last == 0x0D { value.removeLast() }
    return value
  }
}
