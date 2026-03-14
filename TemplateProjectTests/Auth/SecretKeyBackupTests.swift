import XCTest
@testable import TemplateProject

final class SecretKeyBackupTests: XCTestCase {

    func testFormatAndParseRoundTrip() {
        let secret = Data(repeating: 0x42, count: 32)
        let base64url = Base64Utils.encodeURL(secret)
        let formatted = SecretKeyBackup.formatForBackup(base64url)

        XCTAssertTrue(formatted.contains("-"))

        let parsed = try! SecretKeyBackup.parseBackup(formatted)
        let decoded = Base64Utils.decodeURL(parsed)
        XCTAssertEqual(decoded, secret)
    }

    func testFormatProducesBase32Groups() {
        let secret = Data(repeating: 0xAA, count: 32)
        let formatted = SecretKeyBackup.formatForBackup(Base64Utils.encodeURL(secret))
        let groups = formatted.split(separator: "-")
        for group in groups {
            XCTAssertEqual(group.count, 5)
        }
    }

    func testBase32EncodeDecode() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let encoded = SecretKeyBackup.bytesToBase32(data)
        let decoded = try! SecretKeyBackup.base32ToBytes(encoded)
        XCTAssertEqual(decoded, data)
    }

    func testBase32UsesRFC4648Alphabet() {
        let data = Data(repeating: 0xFF, count: 4)
        let encoded = SecretKeyBackup.bytesToBase32(data)
        let validChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        XCTAssertTrue(encoded.unicodeScalars.allSatisfy { validChars.contains($0) })
    }

    func testParseHandlesCommonMistakes() {
        let secret = Data(repeating: 0x55, count: 32)
        let base64url = Base64Utils.encodeURL(secret)
        let formatted = SecretKeyBackup.formatForBackup(base64url)

        let mangled = formatted
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")

        let parsed = try! SecretKeyBackup.parseBackup(mangled)
        let originalParsed = try! SecretKeyBackup.parseBackup(formatted)
        XCTAssertEqual(parsed, originalParsed)
    }

    func testIsValidSecretKey() {
        let secret = Data(repeating: 0x42, count: 32)
        let base64url = Base64Utils.encodeURL(secret)
        let formatted = SecretKeyBackup.formatForBackup(base64url)

        XCTAssertTrue(SecretKeyBackup.isValid(formatted))
        XCTAssertTrue(SecretKeyBackup.isValid(base64url))
        XCTAssertFalse(SecretKeyBackup.isValid("invalid"))
        XCTAssertFalse(SecretKeyBackup.isValid(""))
    }

    func testInvalidBase32Throws() {
        XCTAssertThrowsError(try SecretKeyBackup.parseBackup("!!!"))
    }

    func test32ByteKeyRoundTrip() {
        let secret = Data((0..<32).map { UInt8($0 * 7 + 13) })
        let base64url = Base64Utils.encodeURL(secret)
        let formatted = SecretKeyBackup.formatForBackup(base64url)
        let restored = try! SecretKeyBackup.parseBackup(formatted)
        let restoredBytes = Base64Utils.decodeURL(restored)
        XCTAssertEqual(restoredBytes, secret)
    }
}
