import Foundation
import Security

public struct AetherStoredCredential: Identifiable, Equatable, Sendable {
    public let profileID: UUID
    public let origin: String
    public let username: String
    public var id: String { "\(profileID.uuidString)|\(origin)|\(username)" }
    public init(profileID: UUID, origin: String, username: String) {
        self.profileID = profileID; self.origin = origin; self.username = username
    }
}

public struct AetherCredential: Equatable, Sendable {
    public let profileID: UUID
    public let origin: String
    public let username: String
    public let password: String
}

public enum AetherCredentialVault {
    private static let labelPrefix = "Aether Browser Passwords"

    public static func origin(for rawValue: String) -> String? {
        guard let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        let port = url.port.flatMap { port -> Int? in
            if scheme == "https" && port == 443 { return nil }
            if scheme == "http" && port == 80 { return nil }
            return port
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host.contains(":") ? "[\(host)]" : host
        components.port = port
        return components.string
    }

    public static func credentials(profileID: UUID, origin rawOrigin: String) -> [AetherCredential] {
        guard let origin = origin(for: rawOrigin),
              let match = query(profileID: profileID, origin: origin),
              let rows = attributes(match) else { return [] }
        return rows.compactMap { row in
            guard let username = row[kSecAttrAccount as String] as? String,
                  let password = secret(profileID: profileID, origin: origin, username: username) else { return nil }
            return AetherCredential(profileID: profileID, origin: origin, username: username, password: password)
        }.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }

    public static func saved(profileID: UUID) -> [AetherStoredCredential] {
        let match: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: label(profileID),
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        guard let rows = attributes(match) else { return [] }
        return rows.compactMap { row in
            guard let host = row[kSecAttrServer as String] as? String,
                  let username = row[kSecAttrAccount as String] as? String,
                  let protocolName = row[kSecAttrProtocol as String] as? String,
                  let scheme = protocolName == (kSecAttrProtocolHTTPS as String) ? "https" :
                    (protocolName == (kSecAttrProtocolHTTP as String) ? "http" : nil) else { return nil }
            var parts = URLComponents()
            parts.scheme = scheme
            parts.host = host.contains(":") ? "[\(host)]" : host
            if let port = row[kSecAttrPort as String] as? Int, port > 0 { parts.port = port }
            guard let origin = parts.string else { return nil }
            return AetherStoredCredential(profileID: profileID, origin: origin, username: username)
        }.sorted {
            if $0.origin != $1.origin { return $0.origin < $1.origin }
            return $0.username < $1.username
        }
    }

    @discardableResult
    public static func save(profileID: UUID, origin rawOrigin: String, username: String, password: String) -> Bool {
        guard let origin = origin(for: rawOrigin),
              URL(string: origin)?.scheme == "https",
              !password.isEmpty,
              let pieces = components(for: origin), let data = password.data(using: .utf8) else { return false }
        var identity = identity(profileID: profileID, origin: origin, username: username)
        var values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: label(profileID),
            kSecAttrAuthenticationType as String: kSecAttrAuthenticationTypeHTMLForm,
            kSecAttrProtocol as String: pieces.protocolType,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        identity[kSecAttrServer as String] = pieces.host
        identity[kSecAttrProtocol as String] = pieces.protocolType
        if let port = pieces.port { identity[kSecAttrPort as String] = port }
        let status = SecItemUpdate(identity as CFDictionary, values as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        identity.merge(values) { _, updated in updated }
        let insertionStatus = SecItemAdd(identity as CFDictionary, nil)
        values.removeAll(keepingCapacity: false)
        return insertionStatus == errSecSuccess
    }

    public static func delete(_ item: AetherStoredCredential) -> Bool {
        guard let pieces = components(for: item.origin) else { return false }
        var match = identity(profileID: item.profileID, origin: item.origin, username: item.username)
        match[kSecAttrServer as String] = pieces.host
        match[kSecAttrProtocol as String] = pieces.protocolType
        if let port = pieces.port { match[kSecAttrPort as String] = port }
        let status = SecItemDelete(match as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public static func generatePassword(length: Int = 24) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        var output = [Character]()
        output.reserveCapacity(max(16, length))
        var bytes = [UInt8](repeating: 0, count: max(16, length))
        while output.count < bytes.count {
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard status == errSecSuccess else { return "" }
            output.append(contentsOf: bytes.map { alphabet[Int($0 & 63)] })
        }
        return String(output.prefix(max(16, length)))
    }

    private static func label(_ profileID: UUID) -> String { "\(labelPrefix) (\(profileID.uuidString))" }

    private static func components(for rawOrigin: String) -> (host: String, protocolType: String, port: Int?)? {
        guard let origin = origin(for: rawOrigin), let url = URL(string: origin),
              let host = url.host, let scheme = url.scheme?.lowercased() else { return nil }
        let protocolType: String
        switch scheme {
        case "https": protocolType = kSecAttrProtocolHTTPS as String
        case "http": protocolType = kSecAttrProtocolHTTP as String
        default: return nil
        }
        return (host, protocolType, url.port)
    }

    private static func identity(profileID: UUID, origin: String, username: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: label(profileID),
            kSecAttrAccount as String: username,
        ]
    }

    private static func query(profileID: UUID, origin: String) -> [String: Any]? {
        guard let pieces = components(for: origin) else { return nil }
        var result: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: label(profileID),
            kSecAttrServer as String: pieces.host,
            kSecAttrProtocol as String: pieces.protocolType,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        if let port = pieces.port { result[kSecAttrPort as String] = port }
        return result
    }

    private static func attributes(_ query: [String: Any]) -> [[String: Any]]? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { return nil }
        if let rows = result as? [[String: Any]] { return rows }
        if let row = result as? [String: Any] { return [row] }
        return nil
    }

    private static func secret(profileID: UUID, origin: String, username: String) -> String? {
        guard let pieces = components(for: origin) else { return nil }
        var match = identity(profileID: profileID, origin: origin, username: username)
        match[kSecAttrServer as String] = pieces.host
        match[kSecAttrProtocol as String] = pieces.protocolType
        if let port = pieces.port { match[kSecAttrPort as String] = port }
        match[kSecReturnData as String] = true
        match[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(match as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
