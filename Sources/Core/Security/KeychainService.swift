import Foundation
import Security

public protocol KeychainServiceProtocol: Sendable {
    func savePassword(_ password: String, account: String) throws
    func loadPassword(account: String) throws -> String?
    func deletePassword(account: String) throws
}

public final class KeychainService: KeychainServiceProtocol, Sendable {
    private let service: String

    public init(service: String = "com.parevo.ops.ssh") {
        self.service = service
    }

    public func savePassword(_ password: String, account: String) throws {
        let data = Data(password.utf8)
        try? deletePassword(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw OpsError.keychain("Unable to save credentials (\(status)).")
        }
    }

    public func loadPassword(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw OpsError.keychain("Unable to read credentials (\(status)).")
        }
        return String(data: data, encoding: .utf8)
    }

    public func deletePassword(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpsError.keychain("Unable to delete credentials (\(status)).")
        }
    }
}
