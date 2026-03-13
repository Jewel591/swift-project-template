import Foundation
import Security

struct AuthCredentials: Codable, Equatable {
    let token: String
    let secret: String  // base64url-encoded master secret
}

enum CredentialStoreError: Error {
    case encodingFailed
    case keychainError(OSStatus)
}

enum CredentialStore {

    private static let service = "com.happycoder.auth"
    private static let account = "auth_credentials"

    static func getCredentials() async throws -> AuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialStoreError.keychainError(status)
        }

        return try JSONDecoder().decode(AuthCredentials.self, from: data)
    }

    static func setCredentials(_ credentials: AuthCredentials) async throws {
        let data = try JSONEncoder().encode(credentials)

        // Delete existing item first
        await removeCredentials()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychainError(status)
        }
    }

    static func removeCredentials() async {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
