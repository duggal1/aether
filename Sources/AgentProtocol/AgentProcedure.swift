import Foundation

public protocol AgentProcedure: Sendable {
  associatedtype Input: Codable & Sendable
  associatedtype Output: Codable & Sendable
  static var method: AgentMethod { get }
}

public struct AgentProcedureError: Error, Sendable, Hashable {
  public let code: String
  public let message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }

  public var badParameter: Bool { code == "badParameter" || code == "engine_error" }
}

public enum AgentProcedureCodec {
  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  private static let decoder = JSONDecoder()

  public static func encodeParams<Input: Encodable>(_ input: Input) throws -> [String: JSONValue] {
    let data = try encoder.encode(input)
    return try decoder.decode([String: JSONValue].self, from: data)
  }

  public static func decodeInput<Input: Decodable>(
    _ type: Input.Type, from params: [String: JSONValue]
  ) throws -> Input {
    let data = try encoder.encode(params)
    return try decoder.decode(type, from: data)
  }

  public static func encodeResult<Output: Encodable>(_ output: Output) throws -> JSONValue {
    let data = try encoder.encode(output)
    return try decoder.decode(JSONValue.self, from: data)
  }

  public static func decodeOutput<Output: Decodable>(
    _ type: Output.Type, from value: JSONValue
  ) throws -> Output {
    let data = try encoder.encode(value)
    return try decoder.decode(type, from: data)
  }
}

public struct AgentTypedClient: Sendable {
  private let client: AgentSocketClient
  private let token: String?

  public init(path: String, token: String? = nil) {
    client = AgentSocketClient(path: path)
    self.token = token
  }

  public func call<Procedure: AgentProcedure>(
    _ procedure: Procedure.Type, input: Procedure.Input
  ) throws -> Procedure.Output {
    let params = try AgentProcedureCodec.encodeParams(input)
    let request = AgentRequest(method: Procedure.method, params: params)
    let response: AgentResponse
    if let token {
      response = try client.send(request, token: token)
    } else {
      response = try client.send(request)
    }
    if let error = response.error {
      throw AgentProcedureError(code: error.code, message: error.message)
    }
    guard let result = response.result else {
      throw AgentProcedureError(code: "engine_error", message: "missing result")
    }
    return try AgentProcedureCodec.decodeOutput(Procedure.Output.self, from: result)
  }
}
