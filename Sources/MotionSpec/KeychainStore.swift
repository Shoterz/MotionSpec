import Foundation
import Security

struct KeychainStore: Sendable {
    var service: String

    func savePassword(_ password: String, account: String) throws {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(status)
        }
    }

    func loadPassword(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError.unhandledStatus(status)
        }

        guard let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}

enum KeychainStoreError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unhandledStatus(status):
            return "Keychain error \(status)"
        }
    }
}
