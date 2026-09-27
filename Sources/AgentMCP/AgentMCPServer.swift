import AgentProtocol
import Foundation

public struct AgentMCPServer {
  public typealias AgentCall = (AgentRequest, Int32) throws -> AgentResponse

  private static let modernVersion = "2026-07-28"
  private static let legacyVersion = "2025-11-25"
  private static let supportedVersions = [modernVersion, legacyVersion]
  private static let serverInfo: [String: JSONValue] = [
    "name": .string("Aether"),
    "version": .string("0.2.0"),
  ]

  private struct Request: Decodable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: [String: JSONValue]?

    private enum CodingKeys: String, CodingKey { case jsonrpc, id, method, params }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
      method = try container.decode(String.self, forKey: .method)
      params = try container.decodeIfPresent([String: JSONValue].self, forKey: .params)
      id = container.contains(.id) ? try container.decode(JSONValue.self, forKey: .id) : nil
    }

    var validID: Bool {
      switch id {
      case .string, .integer, .uint: true
      case .number(let value): Int64(exactly: value) != nil
      default: false
      }
    }
  }

  private let callAgent: AgentCall
  private var legacyInitialized = false

  public init(callAgent: @escaping AgentCall) {
    self.callAgent = callAgent
  }

  public mutating func handle(_ message: Data) -> Data? {
    guard message.count <= 8 * 1_024 * 1_024 else {
      return response(id: .null, errorCode: -32600, message: "Message exceeds the 8 MiB limit.")
    }

    let request: Request
    do {
      request = try JSONDecoder().decode(Request.self, from: message)
    } catch {
      return response(id: .null, errorCode: -32700, message: "Parse error.")
    }

    guard request.jsonrpc == "2.0", !request.method.isEmpty else {
      return response(id: request.id ?? .null, errorCode: -32600, message: "Invalid request.")
    }
    guard request.id == nil || request.validID else {
      return response(id: .null, errorCode: -32600, message: "Request id must be a string or integer.")
    }

    if request.method.hasPrefix("notifications/") {
      if request.method == "notifications/initialized" { return nil }
      if request.method == "notifications/cancelled" { return nil }
      return nil
    }

    guard let id = request.id else {
      return response(id: .null, errorCode: -32600, message: "Requests must include an id.")
    }

    if request.method == "initialize" {
      return initialize(request, id: id)
    }
    if request.method == "server/discover" {
      if let error = modernMetadataError(request, id: id) { return error }
      return modernResponse(
        id: id,
        result: [
          "supportedVersions": .array(Self.supportedVersions.map(JSONValue.string)),
          "capabilities": .object(["tools": .object([:])]),
          "_meta": .object(["io.modelcontextprotocol/serverInfo": .object(Self.serverInfo)]),
          "instructions": .string(
            "Aether exposes its existing AgentProtocol methods through a local WebKit runtime. " +
              "Use task.verify to check outcomes; action success is not task success."),
          "ttlMs": .integer(300_000),
          "cacheScope": .string("public"),
        ])
    }

    let modern = request.params?["_meta"] != nil
    if modern {
      if let error = modernMetadataError(request, id: id) { return error }
    } else if !legacyInitialized {
      return response(
        id: id, errorCode: -32600,
        message: "Initialize this legacy MCP client or include 2026-07-28 request metadata.")
    }

    switch request.method {
    case "ping":
      return successResponse(id: id, result: [:], modern: modern)
    case "tools/list":
      let tools = JSONValue.array([Self.agentTool])
      return successResponse(id: id, result: ["tools": tools], modern: modern)
    case "tools/call":
      return callTool(request, id: id, modern: modern)
    default:
      return response(id: id, errorCode: -32601, message: "Method not found: \(request.method)")
    }
  }

  private mutating func initialize(_ request: Request, id: JSONValue) -> Data {
    guard let parameters = request.params,
      let requestedVersion = parameters["protocolVersion"]?.string
    else {
      return response(id: id, errorCode: -32602, message: "Missing protocolVersion.")
    }
    guard requestedVersion == Self.legacyVersion else {
      return response(
        id: id, errorCode: -32602,
        message: "Aether supports MCP \(Self.legacyVersion) legacy or \(Self.modernVersion) modern.")
    }
    legacyInitialized = true
    return response(
      id: id,
      result: [
        "protocolVersion": .string(Self.legacyVersion),
        "capabilities": .object(["tools": .object([:])]),
        "serverInfo": .object(Self.serverInfo),
        "instructions": .string("Aether delegates tool calls to the existing local AgentProtocol runtime."),
      ])
  }

  private func modernMetadataError(_ request: Request, id: JSONValue) -> Data? {
    guard let metadata = request.params?["_meta"]?.object,
      let version = metadata["io.modelcontextprotocol/protocolVersion"]?.string,
      metadata["io.modelcontextprotocol/clientCapabilities"]?.object != nil
    else {
      return response(id: id, errorCode: -32602, message: "Required MCP request metadata is missing.")
    }
    guard version == Self.modernVersion else {
      return unsupportedVersionResponse(id: id, requested: version)
    }
    return nil
  }

  private func callTool(_ request: Request, id: JSONValue, modern: Bool) -> Data {
    guard let parameters = request.params, parameters["name"]?.string == "aether_call" else {
      return response(id: id, errorCode: -32602, message: "Unknown tool.")
    }
    guard let arguments = parameters["arguments"]?.object,
      let method = arguments["method"]?.string,
      let methodParameters = arguments["params"]?.object ?? (arguments["params"] == nil ? [:] : nil)
    else {
      return toolResult(
        id: id, structured: ["error": .object([
          "code": .string("bad_parameter"),
          "message": .string("arguments.method and an object-valued arguments.params are required."),
        ])], isError: true, modern: modern)
    }

    let agentRequest = AgentRequest(method: method, params: methodParameters)
    let timeout = socketTimeout(for: methodParameters)
    do {
      let response = try callAgent(agentRequest, timeout)
      if let error = response.error {
        return toolResult(
          id: id,
          structured: ["error": .object([
            "code": .string(error.code),
            "message": .string(error.message),
          ])],
          isError: true,
          modern: modern)
      }
      return toolResult(
        id: id, structured: ["result": response.result ?? .null],
        isError: false, modern: modern)
    } catch {
      return toolResult(
        id: id,
        structured: ["error": .object([
          "code": .string("transport_error"),
          "message": .string(String(describing: error)),
        ])],
        isError: true,
        modern: modern)
    }
  }

  private func socketTimeout(for parameters: [String: JSONValue]) -> Int32 {
    let requested = parameters["timeoutMs"]?.exactUInt64 ?? 30_000
    return Int32(min(max(requested, 30_000), 600_000))
  }

  private static var agentTool: JSONValue {
    let methods = AgentMethod.allCases.map(\.rawValue).sorted()
    return .object([
      "name": .string("aether_call"),
      "title": .string("Aether AgentProtocol call"),
      "description": .string(
        "Invoke one existing Aether AgentProtocol method against the local Safari/WebKit runtime. " +
          "method is the exact protocol name (for example page.navigate, agent.exec, task.verify, events.recent); " +
          "params are that method's documented input fields. Returns the same structured response as browserctl."),
      "inputSchema": .object([
        "type": .string("object"),
        "properties": .object([
          "method": .object([
            "type": .string("string"),
            "enum": .array(methods.map(JSONValue.string)),
            "description": .string("Exact AgentProtocol method name."),
          ]),
          "params": .object([
            "type": .string("object"),
            "additionalProperties": .bool(true),
            "description": .string("Parameters for the selected AgentProtocol method."),
          ]),
        ]),
        "required": .array([.string("method")]),
        "additionalProperties": .bool(false),
      ]),
    ])
  }

  private func toolResult(
    id: JSONValue,
    structured: [String: JSONValue],
    isError: Bool,
    modern: Bool
  ) -> Data {
    let structuredContent = JSONValue.object(structured)
    let text = (try? String(data: JSONEncoder().encode(structuredContent), encoding: .utf8)) ?? "{}"
    var result: [String: JSONValue] = [
      "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
      "structuredContent": structuredContent,
      "isError": .bool(isError),
    ]
    if modern {
      result["resultType"] = .string("complete")
      result["_meta"] = serverMetadata
    }
    return response(id: id, result: result)
  }

  private func successResponse(
    id: JSONValue, result: [String: JSONValue], modern: Bool
  ) -> Data {
    var value = result
    if modern {
      value["resultType"] = .string("complete")
      value["_meta"] = serverMetadata
    }
    return response(id: id, result: value)
  }

  private func modernResponse(id: JSONValue, result: [String: JSONValue]) -> Data {
    var value = result
    value["resultType"] = .string("complete")
    value["_meta"] = serverMetadata
    return response(id: id, result: value)
  }

  private var serverMetadata: JSONValue {
    .object(["io.modelcontextprotocol/serverInfo": .object(Self.serverInfo)])
  }

  private func unsupportedVersionResponse(id: JSONValue, requested: String) -> Data {
    response(
      id: id, errorCode: -32022, message: "Unsupported protocol version.",
      data: [
        "supported": .array([.string(Self.modernVersion)]),
        "requested": .string(requested),
      ])
  }

  private func response(
    id: JSONValue,
    result: [String: JSONValue]
  ) -> Data {
    encode([
      "jsonrpc": .string("2.0"),
      "id": id,
      "result": .object(result),
    ])
  }

  private func response(
    id: JSONValue,
    errorCode: Int,
    message: String,
    data: [String: JSONValue]? = nil
  ) -> Data {
    var error: [String: JSONValue] = [
      "code": .integer(Int64(errorCode)),
      "message": .string(message),
    ]
    if let data { error["data"] = .object(data) }
    return encode([
      "jsonrpc": .string("2.0"),
      "id": id,
      "error": .object(error),
    ])
  }

  private func encode(_ object: [String: JSONValue]) -> Data {
    var encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(JSONValue.object(object))) ?? Data("{}".utf8)
  }
}
