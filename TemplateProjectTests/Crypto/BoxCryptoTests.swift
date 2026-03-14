import XCTest
@testable import TemplateProject

final class BoxCryptoTests: XCTestCase {

    func testEncryptDecryptRoundTrip() throws {
        let keyPair = BoxCrypto.generateKeyPairFromSeed(Data(repeating: 0xAA, count: 32))
        let plaintext = Data("hello world".utf8)
        let encrypted = try BoxCrypto.encrypt(plaintext, recipientPublicKey: keyPair.publicKey)
        let decrypted = try BoxCrypto.decrypt(encrypted, recipientSecretKey: keyPair.secretKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptedLayout() throws {
        let keyPair = BoxCrypto.generateKeyPairFromSeed(Data(repeating: 0xBB, count: 32))
        let plaintext = Data("test".utf8)
        let encrypted = try BoxCrypto.encrypt(plaintext, recipientPublicKey: keyPair.publicKey)
        XCTAssertGreaterThanOrEqual(encrypted.count, 76)
    }

    func testEphemeralKeyIsRandom() throws {
        let keyPair = BoxCrypto.generateKeyPairFromSeed(Data(repeating: 0xCC, count: 32))
        let plaintext = Data("same".utf8)
        let enc1 = try BoxCrypto.encrypt(plaintext, recipientPublicKey: keyPair.publicKey)
        let enc2 = try BoxCrypto.encrypt(plaintext, recipientPublicKey: keyPair.publicKey)
        XCTAssertNotEqual(Data(enc1.prefix(32)), Data(enc2.prefix(32)))
    }

    func testDecryptWithWrongKeyFails() throws {
        let kp1 = BoxCrypto.generateKeyPairFromSeed(Data(repeating: 0x01, count: 32))
        let kp2 = BoxCrypto.generateKeyPairFromSeed(Data(repeating: 0x02, count: 32))
        let encrypted = try BoxCrypto.encrypt(Data("secret".utf8), recipientPublicKey: kp1.publicKey)
        XCTAssertNil(BoxCrypto.decryptOrNil(encrypted, recipientSecretKey: kp2.secretKey))
    }

    func testSeedKeyPairDeterministic() {
        let seed = Data(repeating: 0xDD, count: 32)
        let kp1 = BoxCrypto.generateKeyPairFromSeed(seed)
        let kp2 = BoxCrypto.generateKeyPairFromSeed(seed)
        XCTAssertEqual(kp1.publicKey, kp2.publicKey)
        XCTAssertEqual(kp1.secretKey, kp2.secretKey)
    }
}
