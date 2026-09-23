import AetherHumanUI
import EngineRuntime
import Foundation
import Network

private struct ProxyCredential: Codable, Sendable {
  var username: String
  var password: String
}

extension AetherEngineAdapter: BrowserNetworkRouting {
  func currentRouteStatus(profileID: UUID) -> NetworkRouteStatus {
    routeStatus[profileID] ?? .unknown
  }

  func observedExitIP(profileID: UUID) -> String? {
    observedExitIPs[profileID]
  }

  func applyNetworkRoute(profileID: UUID, route: BrowserNetworkRoute,
    endpoint: RouteEndpoint?
  ) async throws -> NetworkRouteStatus {
    let context = try await context(for: profileID)
    guard route.enabled, route.region != .direct else {
      try await engine.runtime.configureWebProxy(contextID: context, endpoint: nil)
      routeStatus[profileID] = .direct
      observedExitIPs[profileID] = nil
      return .direct
    }
    guard let endpoint else {
      if route.failClosed {
        try await engine.runtime.configureWebProxy(
          contextID: context, endpoint: .failClosedBlackhole)
        routeStatus[profileID] = .blocked
      } else {
        try await engine.runtime.configureWebProxy(contextID: context, endpoint: nil)
        routeStatus[profileID] = .unavailable
      }
      observedExitIPs[profileID] = nil
      return routeStatus[profileID] ?? .unknown
    }
    routeStatus[profileID] = .connecting
    let account = AetherKeychain.proxyCredentialAccount(endpointID: endpoint.id)
    var username: String?
    var password: String?
    if let stored = try? AetherKeychain().load(account: account),
      let credential = try? JSONDecoder().decode(ProxyCredential.self, from: stored) {
      username = credential.username
      password = credential.password
    }
    let resolved = WebProxyEndpoint(
      host: endpoint.host, port: endpoint.port, username: username, password: password,
      failClosed: route.failClosed)
    try await engine.runtime.configureWebProxy(contextID: context, endpoint: resolved)
    guard let observed = await probeExitIP(proxy: resolved) else {
      observedExitIPs[profileID] = nil
      if route.failClosed {
        routeStatus[profileID] = .blocked
        return .blocked
      }
      routeStatus[profileID] = .unavailable
      return .unavailable
    }
    observedExitIPs[profileID] = observed
    if let expected = endpoint.expectedExitIP?.trimmingCharacters(in: .whitespacesAndNewlines),
      !expected.isEmpty, expected != observed {
      routeStatus[profileID] = .unavailable
      return .unavailable
    }
    routeStatus[profileID] = .connected
    return .connected
  }

  func saveProxyCredential(endpointID: String, username: String, password: String) throws {
    let account = AetherKeychain.proxyCredentialAccount(endpointID: endpointID)
    if username.isEmpty, password.isEmpty {
      try AetherKeychain().delete(account: account)
      return
    }
    let credential = ProxyCredential(username: username, password: password)
    let data = try JSONEncoder().encode(credential)
    try AetherKeychain().save(data, account: account)
  }

  private func probeExitIP(proxy: WebProxyEndpoint) async -> String? {
    guard let url = URL(string: "https://api.ipify.org?format=json"),
      let port = NWEndpoint.Port(rawValue: proxy.port)
    else { return nil }
    var configuration = ProxyConfiguration(
      socksv5Proxy: .hostPort(host: .name(proxy.host, nil), port: port))
    configuration.allowFailover = false
    if let username = proxy.username, let password = proxy.password {
      configuration.applyCredential(username: username, password: password)
    }
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.proxyConfigurations = [configuration]
    sessionConfiguration.timeoutIntervalForRequest = 8
    sessionConfiguration.timeoutIntervalForResource = 8
    let session = URLSession(configuration: sessionConfiguration)
    guard let (data, response) = try? await session.data(from: url),
      let http = response as? HTTPURLResponse, http.statusCode == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let ip = object["ip"] as? String, !ip.isEmpty
    else { return nil }
    return ip
  }
}

extension AetherEngineAdapter: BrowserProxyCredentialStoring {
  func deleteProxyCredential(endpointID: String) throws {
    try AetherKeychain().delete(account: AetherKeychain.proxyCredentialAccount(endpointID: endpointID))
  }
}
