import Foundation
import CryptoKit

enum AESGCMCryptoError: Error {
    case invalidVersion
    case dataTooShort
    case decryptionFailed
    case serializationFailed
}

enum AESGCMCrypto {

    /// Encrypt a Codable value to: [version(1) | nonce(12) | ciphertext | authTag(16)]
    /// Mirrors: AES256Encryption.encrypt() in encryptor.ts
    static func encrypt<T: Encodable>(_ value: T, key: Data) throws -> Data {
        let json = try JSONEncoder().encode(value)
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.seal(json, using: symmetricKey)

        // Layout: [version(1) | nonce(12) | ciphertext | tag(16)]
        var result = Data([0x00])                    // version byte
        result.append(sealedBox.nonce.withUnsafeBytes { Data($0) })  // 12 bytes
        result.append(sealedBox.ciphertext)          // variable
        result.append(sealedBox.tag)                 // 16 bytes
        return result
    }

    /// Decrypt data back to a Codable value.
    /// Mirrors: AES256Encryption.decrypt() in encryptor.ts
    static func decrypt<T: Decodable>(_ data: Data, key: Data) throws -> T {
        // Minimum: version(1) + nonce(12) + tag(16) = 29
        guard data.count >= 29 else { throw AESGCMCryptoError.dataTooShort }
        guard data[0] == 0x00 else { throw AESGCMCryptoError.invalidVersion }

        let nonce = try AES.GCM.Nonce(data: data[1..<13])
        let ciphertext = data[13..<(data.count - 16)]
        let tag = data[(data.count - 16)...]

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let symmetricKey = SymmetricKey(data: key)
        let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)

        return try JSONDecoder().decode(T.self, from: plaintext)
    }
}
