import Foundation
import Sodium

struct ChallengeResult {
    let challenge: Data   // 32 bytes random
    let signature: Data   // 64 bytes Ed25519
    let publicKey: Data   // 32 bytes Ed25519
}

enum AuthChallenge {

    private static let sodium = Sodium()

    /// Create a signed challenge for authentication.
    /// Mirrors: authChallenge(secret) in authChallenge.ts
    static func create(secret: Data) -> ChallengeResult {
        let seedBytes = Bytes(secret)
        let keypair = sodium.sign.keyPair(seed: seedBytes)!

        let challenge = Data(sodium.randomBytes.buf(length: 32)!)

        let signature = sodium.sign.signature(
            message: Bytes(challenge),
            secretKey: keypair.secretKey
        )!

        return ChallengeResult(
            challenge: challenge,
            signature: Data(signature),
            publicKey: Data(keypair.publicKey)
        )
    }

    /// Verify a signature (for testing).
    static func verify(signature: Data, message: Data, publicKey: Data) -> Bool {
        sodium.sign.verify(
            message: Bytes(message),
            publicKey: Bytes(publicKey),
            signature: Bytes(signature)
        )
    }
}
