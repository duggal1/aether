import AgentMCP
import AgentProtocol
import Foundation
import Testing

@Test func legacyMCPCallsForwardAgentMethodsAndReturnStructuredResults() throws {
  var forwardedMethod: String?
  var forwardedTimeout: Int32?
  var server = AgentMCPServer { request, timeout in
    forwardedMethod = request.method
    forwardedTimeout = timeout
    return AgentResponse(
      id: request.id,
      result: .object(["ok": .bool(true), "method": .string(request.method)]))
  }

  let initialized = try server.handle(message: message([
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"]],
  ]))
  #expect(initialized["result"]?["protocolVersion"]?.string == "2025-11-25")

  let listed = try server.handle(message: message([
    "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": [:],
  ]))
  #expect(listed["result"]?["tools"]?.array?.count == 1)
  #expect(listed["result"]?["tools"]?.array?.first?["name"]?.string == "aether_call")

  let called = try server.handle(message: message([
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": [
      "name": "aether_call",
      "arguments": [
        "method": "task.verify",
        "params": ["timeoutMs": 700_000, "plan": ["page": 8, "checks": []]],
      ],
    ],
  ]))
  #expect(called["result"]?["isError"]?.bool == false)
  #expect(called["result"]?["structuredContent"]?["result"]?["ok"]?.bool == true)
  #expect(forwardedMethod == "task.verify")
  #expect(forwardedTimeout == 600_000)
}

@Test func modernMCPRequiresRequestMetadataAndUsesModernResultEnvelope() throws {
  var server = AgentMCPServer { request, _ in
    AgentResponse(id: request.id, result: .object(["value": .integer(7)]))
  }
  let metadata: [String: Any] = [
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": [:],
  ]
  let discovered = try server.handle(message: message([
    "jsonrpc": "2.0", "id": "discovery", "method": "server/discover",
    "params": ["_meta": metadata],
  ]))
  #expect(discovered["result"]?["resultType"]?.string == "complete")
  #expect(discovered["result"]?["supportedVersions"]?.array?.contains(.string("2026-07-28")) == true)

  let called = try server.handle(message: message([
    "jsonrpc": "2.0", "id": 10, "method": "tools/call",
    "params": [
      "_meta": metadata,
      "name": "aether_call",
      "arguments": ["method": "ping", "params": [:]],
    ],
  ]))
  #expect(called["result"]?["resultType"]?.string == "complete")
  #expect(called["result"]?["structuredContent"]?["result"]?["value"]?.number == 7)
}

@Test func modernMCPRejectsMissingMetadataAndReportsAgentErrorsAsToolErrors() throws {
  var server = AgentMCPServer { request, _ in
    AgentResponse(id: request.id, error: AgentError(code: "unauthorized", message: "denied"))
  }
  let missingMetadata = try server.handle(message: message([
    "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": [:],
  ]))
  #expect(missingMetadata["error"]?["code"]?.number == -32600)

  let metadata: [String: Any] = [
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": [:],
  ]
  let called = try server.handle(message: message([
    "jsonrpc": "2.0", "id": 2, "method": "tools/call",
    "params": [
      "_meta": metadata,
      "name": "aether_call",
      "arguments": ["method": "page.click", "params": ["page": 1]],
    ],
  ]))
  #expect(called["result"]?["isError"]?.bool == true)
  #expect(called["result"]?["structuredContent"]?["error"]?["code"]?.string == "unauthorized")
}

private func message(_ value: [String: Any]) throws -> Data {
  try JSONSerialization.data(withJSONObject: value)
}

private extension AgentMCPServer {
  mutating func handle(message: Data) throws -> JSONValue {
    guard let data = handle(message) else {
      throw MCPTestError.missingResponse
    }
    return try JSONDecoder().decode(JSONValue.self, from: data)
  }
}

private enum MCPTestError: Error {
  case missingResponse
}
