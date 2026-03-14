import XCTest
@testable import TemplateProject

final class SecretBoxCryptoTests: XCTestCase {

    func testEncryptDecryptRoundTrip() throws {
        let key = Data(repeating: 0xAA, count: 32)
        let original = ["message": "hello world"]
        let encrypted = try SecretBoxCrypto.encrypt(original, key: key)
        let decrypted: [String: String] = try SecretBoxCrypto.decrypt(encrypted, key: key)
        XCTAssertEqual(decrypted["message"], "hello world")
    }

    func testEncryptedStartsWithNonce() throws {
        let key = Data(repeating: 0xBB, count: 32)
        let encrypted = try SecretBoxCrypto.encrypt(["x": 1], key: key)
        // Minimum: nonce(24) + poly1305_tag(16) + at least 1 byte ciphertext
        XCTAssertGreaterThanOrEqual(encrypted.count, 41)
    }

    func testNonceIsRandom() throws {
        let key = Data(repeating: 0xCC, count: 32)
        let data = ["same": "data"]
        let enc1 = try SecretBoxCrypto.encrypt(data, key: key)
        let enc2 = try SecretBoxCrypto.encrypt(data, key: key)
        XCTAssertNotEqual(enc1, enc2) // Different nonces
    }

    func testDecryptWithWrongKeyReturnsNil() throws {
        let key1 = Data(repeating: 0x01, count: 32)
        let key2 = Data(repeating: 0x02, count: 32)
        let encrypted = try SecretBoxCrypto.encrypt(["secret": true], key: key1)
        let result: [String: Bool]? = SecretBoxCrypto.decryptOrNil(encrypted, key: key2)
        XCTAssertNil(result)
    }
}
