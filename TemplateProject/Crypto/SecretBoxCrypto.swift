import Foundation
import Sodium

enum SecretBoxCryptoError: Error {
    case encryptionFailed
    case decryptionFailed
    case serializationFailed
}

enum SecretBoxCrypto {

    private static let sodium = Sodium()

    /// Encrypt a Codable value to: [nonce(24) | ciphertext+tag]
    /// Mirrors: encryptSecretBox() in libsodium.ts
    static func encrypt<T: Encodable>(_ value: T, key: Data) throws -> Data {
        let json = try JSONEncoder().encode(value)
        let keyBytes = Bytes(key)

        guard let encrypted: Bytes = sodium.secretBox.seal(
            message: Bytes(json),
            secretKey: keyBytes
        ) else {
            throw SecretBoxCryptoError.encryptionFailed
        }

        // sodium.secretBox.seal already returns [nonce(24) | ciphertext+tag]
        return Data(encrypted)
    }

    /// Decrypt data back to a Codable value. Throws on failure.
    /// Mirrors: decryptSecretBox() in libsodium.ts
    static func decrypt<T: Decodable>(_ data: Data, key: Data) throws -> T {
        let keyBytes = Bytes(key)

        guard let decrypted = sodium.secretBox.open(
            nonceAndAuthenticatedCipherText: Bytes(data),
            secretKey: keyBytes
        ) else {
            throw SecretBoxCryptoError.decryptionFailed
        }

        return try JSONDecoder().decode(T.self, from: Data(decrypted))
    }

    /// Decrypt, returning nil on failure instead of throwing.
    static func decryptOrNil<T: Decodable>(_ data: Data, key: Data) -> T? {
        try? decrypt(data, key: key)
    }
}
