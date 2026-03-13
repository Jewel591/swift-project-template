import XCTest
@testable import TemplateProject

final class EncryptionIntegrationTests: XCTestCase {

    /// Test the full Happy encryption key hierarchy:
    /// masterSecret → contentDataKey → contentKeyPair → DEK encrypt/decrypt
    func testFullKeyHierarchy() throws {
        // 1. Simulate a 32-byte master secret (received from QR auth)
        let masterSecret = Data(repeating: 0x42, count: 32)

        // 2. Derive content data key (mirrors Encryption.create() in encryption.ts)
        let contentDataKey = KeyDerivation.deriveKey(
            master: masterSecret,
            usage: "Happy EnCoder",
            path: ["content"]
        )
        XCTAssertEqual(contentDataKey.count, 32)

        // 3. Generate content keypair from contentDataKey
        let contentKeyPair = BoxCrypto.generateKeyPairFromSeed(contentDataKey)
        XCTAssertEqual(contentKeyPair.publicKey.count, 32)
        XCTAssertEqual(contentKeyPair.secretKey.count, 32)

        // 4. Generate a session-specific DEK (data encryption key)
        let sessionDEK = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        // 5. Wrap (encrypt) DEK: [0x00 | encryptBox(DEK, contentKeyPair.publicKey)]
        let encryptedDEK_inner = try BoxCrypto.encrypt(sessionDEK, recipientPublicKey: contentKeyPair.publicKey)
        var wrappedDEK = Data([0x00])
        wrappedDEK.append(encryptedDEK_inner)

        // 6. Unwrap (decrypt) DEK
        XCTAssertEqual(wrappedDEK[0], 0x00)
        let unwrappedDEK = try BoxCrypto.decrypt(Data(wrappedDEK[1...]), recipientSecretKey: contentKeyPair.secretKey)
        XCTAssertEqual(unwrappedDEK, sessionDEK)

        // 7. Use DEK to encrypt/decrypt a message with AES-GCM
        let message = TestSessionMessage(role: "session", text: "Hello from Swift!")
        let encrypted = try AESGCMCrypto.encrypt(message, key: unwrappedDEK)
        let decrypted: TestSessionMessage = try AESGCMCrypto.decrypt(encrypted, key: unwrappedDEK)
        XCTAssertEqual(decrypted.role, "session")
        XCTAssertEqual(decrypted.text, "Hello from Swift!")

        // 8. Also test legacy path: SecretBox with masterSecret directly
        let legacyEncrypted = try SecretBoxCrypto.encrypt(message, key: masterSecret)
        let legacyDecrypted: TestSessionMessage = try SecretBoxCrypto.decrypt(legacyEncrypted, key: masterSecret)
        XCTAssertEqual(legacyDecrypted.text, "Hello from Swift!")

        // 9. Derive anon ID (mirrors encryption.ts)
        let anonIDKey = KeyDerivation.deriveKey(
            master: masterSecret,
            usage: "Happy Coder",
            path: ["analytics", "id"]
        )
        let anonID = String(HexUtils.encode(anonIDKey).prefix(16)).lowercased()
        XCTAssertEqual(anonID.count, 16)
    }
}

private struct TestSessionMessage: Codable, Equatable {
    let role: String
    let text: String
}
