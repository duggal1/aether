import Foundation

public enum AetherExitRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case direct
    case sanFrancisco = "San Francisco"
    case newYork = "New York"
    case boston = "Boston"
    case philadelphia = "Philadelphia"
    public var id: String { rawValue }

    public var subtitle: String {
        switch self {
        case .direct: "No remote routing; websites see this Mac's public IP."
        case .sanFrancisco: "Fixed West Coast exit presence."
        case .newYork: "Northeast exit for geographic separation."
        case .boston: "Alternative Northeast exit."
        case .philadelphia: "Alternative Northeast exit."
        }
    }
}

public struct BrowserNetworkRoute: Codable, Equatable, Sendable {
    public var region: AetherExitRegion
    public var enabled: Bool
    public var failClosed: Bool
    public var endpointID: String?

    public init(region: AetherExitRegion = .direct, enabled: Bool = false,
                failClosed: Bool = true, endpointID: String? = nil) {
        self.region = region
        self.enabled = enabled
        self.failClosed = failClosed
        self.endpointID = endpointID
    }

    public static let direct = BrowserNetworkRoute()
}

public struct RouteEndpoint: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var host: String
    public var port: UInt16
    public var region: AetherExitRegion
    public var expectedExitIP: String?

    public init(id: String = UUID().uuidString, host: String, port: UInt16,
                region: AetherExitRegion, expectedExitIP: String? = nil) {
        self.id = id
        self.host = host
        self.port = port
        self.region = region
        self.expectedExitIP = expectedExitIP
    }
}

public enum NetworkRouteStatus: String, Sendable, Equatable {
    case direct
    case connecting
    case connected
    case unavailable
    case blocked
    case unknown

    public var label: String {
        switch self {
        case .direct: "Direct connection"
        case .connecting: "Connecting to remote exit"
        case .connected: "Remote exit connected"
        case .unavailable: "Remote exit unavailable"
        case .blocked: "Connection blocked"
        case .unknown: "Privacy status unknown"
        }
    }

    public var claimsHiddenIP: Bool { self == .connected }
}

public struct SearchLocality: Codable, Equatable, Sendable {
    public var countryCode: String
    public var regionCode: String
    public var city: String
    public var postalCode: String?
    public var nearbyPostalCodes: [String]

    public init(countryCode: String, regionCode: String, city: String,
                postalCode: String? = nil, nearbyPostalCodes: [String] = []) {
        self.countryCode = countryCode
        self.regionCode = regionCode
        self.city = city
        self.postalCode = postalCode
        self.nearbyPostalCodes = nearbyPostalCodes
    }

    public static let sanFrancisco = SearchLocality(
        countryCode: "US", regionCode: "CA", city: "San Francisco",
        postalCode: "94158", nearbyPostalCodes: ["94105", "94103", "94110"])

    public var summary: String {
        [city, regionCode, postalCode].compactMap { $0 }.joined(separator: " · ")
    }
}
