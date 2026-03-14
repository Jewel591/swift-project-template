import Testing
import Foundation
@testable import TemplateProject

@Suite("QRAuthFlow Tests")
struct QRAuthFlowTests {

    @Test("Generate QR payload produces valid keypair")
    func generatePayload() throws {
        let payload = try QRAuthFlow.generateQRPayload()

        #expect(payload.publicKey.count == 32)
        #expect(payload.secretKey.count == 32)
        #expect(!payload.qrString.isEmpty)

        // QR string should be valid base64 that decodes to the public key
        let decoded = Base64Utils.decode(payload.qrString)
        #expect(decoded == payload.publicKey)
    }

    @Test("Each payload generates unique keypairs")
    func uniqueKeypairs() throws {
        let payload1 = try QRAuthFlow.generateQRPayload()
        let payload2 = try QRAuthFlow.generateQRPayload()

        #expect(payload1.publicKey != payload2.publicKey)
        #expect(payload1.secretKey != payload2.secretKey)
    }

    @Test("Encrypt and decrypt master secret round-trip")
    func encryptDecryptRoundTrip() throws {
        let payload = try QRAuthFlow.generateQRPayload()
        let masterSecret = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        // Simulate desktop encrypting to mobile's public key
        let encrypted = try QRAuthFlow.encryptForRecipient(
            masterSecret: masterSecret,
            recipientPublicKey: payload.publicKey
        )

        // Mobile decrypts with its secret key
        let decrypted = try QRAuthFlow.decryptMasterSecret(
            encryptedBase64: encrypted,
            recipientSecretKey: payload.secretKey
        )

        #expect(decrypted == masterSecret)
        #expect(decrypted.count == 32)
    }

    @Test("Decrypt fails with wrong key")
    func wrongKeyFails() throws {
        let payload1 = try QRAuthFlow.generateQRPayload()
        let payload2 = try QRAuthFlow.generateQRPayload()
        let masterSecret = Data(repeating: 0x42, count: 32)

        // Encrypt to payload1's public key
        let encrypted = try QRAuthFlow.encryptForRecipient(
            masterSecret: masterSecret,
            recipientPublicKey: payload1.publicKey
        )

        // Try to decrypt with payload2's secret key — should fail
        #expect(throws: QRAuthError.self) {
            try QRAuthFlow.decryptMasterSecret(
                encryptedBase64: encrypted,
                recipientSecretKey: payload2.secretKey
            )
        }
    }

    @Test("Decrypt rejects invalid base64")
    func invalidBase64() throws {
        let payload = try QRAuthFlow.generateQRPayload()

        #expect(throws: QRAuthError.self) {
            try QRAuthFlow.decryptMasterSecret(
                encryptedBase64: "not!valid!base64!@#$",
                recipientSecretKey: payload.secretKey
            )
        }
    }

    @Test("Decrypt rejects too-short secret")
    func tooShortSecret() throws {
        let payload = try QRAuthFlow.generateQRPayload()

        // Encrypt a 16-byte value (too short, should be 32)
        let shortSecret = Data(repeating: 0xAA, count: 16)
        let encrypted = try BoxCrypto.encrypt(shortSecret, recipientPublicKey: payload.publicKey)
        let encryptedBase64 = Base64Utils.encode(encrypted)

        #expect(throws: QRAuthError.self) {
            try QRAuthFlow.decryptMasterSecret(
                encryptedBase64: encryptedBase64,
                recipientSecretKey: payload.secretKey
            )
        }
    }
}
