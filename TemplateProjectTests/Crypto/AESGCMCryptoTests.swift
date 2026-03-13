import XCTest
@testable import TemplateProject

final class AESGCMCryptoTests: XCTestCase {

    func testEncryptDecryptRoundTrip() throws {
        let key = Data(repeating: 0xAA, count: 32)
        let plaintext = ["hello": "world"]
        let encrypted = try AESGCMCrypto.encrypt(plaintext, key: key)
        let decrypted: [String: String] = try AESGCMCrypto.decrypt(encrypted, key: key)
        XCTAssertEqual(decrypted["hello"], "world")
    }

    func testEncryptedDataStartsWithVersionByte() throws {
        let key = Data(repeating: 0xBB, count: 32)
        let encrypted = try AESGCMCrypto.encrypt(["key": "value"], key: key)
        XCTAssertEqual(encrypted[0], 0x00)
    }

    func testEncryptedMinimumSize() throws {
        let key = Data(repeating: 0xCC, count: 32)
        let encrypted = try AESGCMCrypto.encrypt(["a": 1], key: key)
        XCTAssertGreaterThanOrEqual(encrypted.count, 29)
    }

    func testDecryptWithWrongKeyFails() throws {
        let key1 = Data(repeating: 0x01, count: 32)
        let key2 = Data(repeating: 0x02, count: 32)
        let encrypted = try AESGCMCrypto.encrypt(["secret": true], key: key1)
        XCTAssertThrowsError(try AESGCMCrypto.decrypt(encrypted, key: key2) as [String: Bool])
    }

    func testDecryptWithWrongVersionFails() throws {
        let key = Data(repeating: 0xDD, count: 32)
        var encrypted = try AESGCMCrypto.encrypt(["x": 1], key: key)
        encrypted[0] = 0x01
        XCTAssertThrowsError(try AESGCMCrypto.decrypt(encrypted, key: key) as [String: Int])
    }

    func testNestedJSON() throws {
        let key = Data(repeating: 0xEE, count: 32)
        let msg = TestMessage(role: "session", text: "hello")
        let encrypted = try AESGCMCrypto.encrypt(msg, key: key)
        let decrypted: TestMessage = try AESGCMCrypto.decrypt(encrypted, key: key)
        XCTAssertEqual(decrypted.role, "session")
        XCTAssertEqual(decrypted.text, "hello")
    }
}

private struct TestMessage: Codable, Equatable {
    let role: String
    let text: String
}
