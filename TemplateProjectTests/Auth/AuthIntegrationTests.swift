import Testing
import Foundation
@testable import TemplateProject

@Suite("Auth Integration Tests")
struct AuthIntegrationTests {

    @Test("Full offline auth flow: keypair → QR → encrypt → decrypt → challenge → verify → backup")
    func fullOfflineFlow() throws {
        // Step 1: Mobile generates ephemeral Box keypair for QR
        let qrPayload = try QRAuthFlow.generateQRPayload()
        #expect(qrPayload.publicKey.count == 32)
        #expect(qrPayload.secretKey.count == 32)

        // Step 2: Generate a master secret (simulates what the user would have)
        let masterSecret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        // Step 3: Desktop encrypts master secret to mobile's QR public key
        let encryptedBase64 = try QRAuthFlow.encryptForRecipient(
            masterSecret: masterSecret,
            recipientPublicKey: qrPayload.publicKey
        )
        #expect(!encryptedBase64.isEmpty)

        // Step 4: Mobile decrypts to recover master secret
        let recoveredSecret = try QRAuthFlow.decryptMasterSecret(
            encryptedBase64: encryptedBase64,
            recipientSecretKey: qrPayload.secretKey
        )
        #expect(recoveredSecret == masterSecret)

        // Step 5: Mobile creates challenge-response using recovered secret
        let challengeResult = AuthChallenge.create(secret: recoveredSecret)
        #expect(challengeResult.challenge.count == 32)
        #expect(challengeResult.signature.count == 64)
        #expect(challengeResult.publicKey.count == 32)

        // Step 6: Server verifies signature
        let verified = AuthChallenge.verify(
            signature: challengeResult.signature,
            message: challengeResult.challenge,
            publicKey: challengeResult.publicKey
        )
        #expect(verified)

        // Step 7: Public key is deterministic from the same secret
        let challengeResult2 = AuthChallenge.create(secret: recoveredSecret)
        #expect(challengeResult2.publicKey == challengeResult.publicKey)
        // But challenges should be unique
        #expect(challengeResult2.challenge != challengeResult.challenge)

        // Step 8: Tampered signature fails verification
        var tamperedSig = challengeResult.signature
        tamperedSig[0] ^= 0xFF
        let tamperedResult = AuthChallenge.verify(
            signature: tamperedSig,
            message: challengeResult.challenge,
            publicKey: challengeResult.publicKey
        )
        #expect(!tamperedResult)

        // Step 9: Backup format round-trip
        let backupString = SecretKeyBackup.encode(masterSecret)
        #expect(!backupString.isEmpty)
        #expect(backupString.contains("-"))  // Human-friendly format

        let restoredSecret = try SecretKeyBackup.decode(backupString)
        #expect(restoredSecret == masterSecret)

        // Step 10: Verify key derivation produces encryption keys
        let encKey = try KeyDerivation.deriveEncryptionKey(from: masterSecret)
        #expect(encKey.count == 32)

        let boxKP = BoxCrypto.generateKeyPairFromSeed(masterSecret)
        #expect(boxKP.publicKey.count == 32)
        #expect(boxKP.secretKey.count == 32)
    }

    @Test("Different master secrets produce different public keys")
    func differentSecretsDifferentKeys() {
        let secret1 = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let secret2 = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        let result1 = AuthChallenge.create(secret: secret1)
        let result2 = AuthChallenge.create(secret: secret2)

        #expect(result1.publicKey != result2.publicKey)
    }

    @Test("Backup format handles common OCR mistakes")
    func backupOCRMistakes() throws {
        let secret = Data(repeating: 0x42, count: 32)
        let encoded = SecretKeyBackup.encode(secret)

        // Introduce common OCR mistakes
        let withMistakes = encoded
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")

        let decoded = try SecretKeyBackup.decode(withMistakes)
        #expect(decoded == secret)
    }
}
