import Foundation
import Sodium

struct BoxKeyPair {
    let publicKey: Data   // 32 bytes
    let secretKey: Data   // 32 bytes
}

enum BoxCryptoError: Error {
    case encryptionFailed
    case decryptionFailed
    case invalidBundle
}

enum BoxCrypto {

    private static let sodium = Sodium()

    /// Generate X25519 keypair from 32-byte seed.
    /// Mirrors: sodium.crypto_box_seed_keypair(seed) in libsodium.ts
    static func generateKeyPairFromSeed(_ seed: Data) -> BoxKeyPair {
        let kp = sodium.box.keyPair(seed: Bytes(seed))!
        return BoxKeyPair(publicKey: Data(kp.publicKey), secretKey: Data(kp.secretKey))
    }

    /// Encrypt data with ephemeral keypair.
    /// Output: [ephemeralPublicKey(32) | nonce(24) | ciphertext+tag]
    /// Mirrors: encryptBox() in libsodium.ts
    static func encrypt(_ data: Data, recipientPublicKey: Data) throws -> Data {
        let ephemeralKP = sodium.box.keyPair()!
        let nonce = sodium.box.nonce()

        guard let encrypted = sodium.box.seal(
            message: Bytes(data),
            recipientPublicKey: Bytes(recipientPublicKey),
            senderSecretKey: ephemeralKP.secretKey,
            nonce: nonce
        ) else {
            throw BoxCryptoError.encryptionFailed
        }

        var result = Data(ephemeralKP.publicKey)  // 32 bytes
        result.append(Data(nonce))                // 24 bytes
        result.append(Data(encrypted))            // ciphertext + tag
        return result
    }

    /// Decrypt data encrypted with encrypt().
    /// Mirrors: decryptBox() in libsodium.ts
    static func decrypt(_ bundle: Data, recipientSecretKey: Data) throws -> Data {
        guard bundle.count >= 72 else { throw BoxCryptoError.invalidBundle }

        let ephemeralPK = Bytes(bundle[0..<32])
        let nonce = Bytes(bundle[32..<56])
        let ciphertext = Bytes(bundle[56...])

        guard let decrypted = sodium.box.open(
            authenticatedCipherText: ciphertext,
            senderPublicKey: ephemeralPK,
            recipientSecretKey: Bytes(recipientSecretKey),
            nonce: nonce
        ) else {
            throw BoxCryptoError.decryptionFailed
        }

        return Data(decrypted)
    }

    /// Decrypt, returning nil on failure.
    static func decryptOrNil(_ bundle: Data, recipientSecretKey: Data) -> Data? {
        try? decrypt(bundle, recipientSecretKey: recipientSecretKey)
    }
}
