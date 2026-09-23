import Foundation
import Security

public enum AetherKeychainError: Error, Equatable, Sendable {
    case invalidData
    case unexpectedStatus(OSStatus)

    public var message: String {
        switch self {
        case .invalidData: "The Keychain returned unusable data."
        case .unexpectedStatus(let status): "The Keychain refused the request (status \(status))."
        }
    }
}

public struct AetherKeychain: Sendable {
    public static let service = "fun.aether.secure-storage"
    public init() {}

    public static func credentialAccount(profileID: UUID, provider: String, accountID: String) -> String {
        [profileID.uuidString, provider, accountID].joined(separator: ":")
    }

    public static func proxyCredentialAccount(endpointID: String) -> String {
        "proxy:" + endpointID
    }

    public func save(_ value: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        if status != errSecItemNotFound { throw AetherKeychainError.unexpectedStatus(status) }
        var insertion = query
        for (key, entry) in attributes { insertion[key] = entry }
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AetherKeychainError.unexpectedStatus(addStatus)
        }
    }

    public func save(_ text: String, account: String) throws {
        guard let data = text.data(using: .utf8) else { throw AetherKeychainError.invalidData }
        try save(data, account: account)
    }

    public func load(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AetherKeychainError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw AetherKeychainError.invalidData }
        return data
    }

    public func loadText(account: String) throws -> String? {
        guard let data = try load(account: account) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { throw AetherKeychainError.invalidData }
        return text
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AetherKeychainError.unexpectedStatus(status)
        }
    }

    public func contains(account: String) throws -> Bool {
        try load(account: account) != nil
    }
}
