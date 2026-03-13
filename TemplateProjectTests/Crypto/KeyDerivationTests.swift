import XCTest
import CryptoKit
@testable import TemplateProject

final class KeyDerivationTests: XCTestCase {

    func testHMACSHA512OutputLength() {
        let key = Data(repeating: 0x0B, count: 20)
        let data = Data("Hi There".utf8)
        let result = KeyDerivation.hmacSHA512(key: key, data: data)
        XCTAssertEqual(result.count, 64)
    }

    func testHMACSHA512RFC4231Vector1() {
        let key = Data(repeating: 0x0B, count: 20)
        let data = Data("Hi There".utf8)
        let result = KeyDerivation.hmacSHA512(key: key, data: data)
        let hex = HexUtils.encode(result)
        XCTAssertEqual(hex, "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854")
    }

    func testDeriveKeyOutputLength() {
        let master = Data(repeating: 0x01, count: 32)
        let key = KeyDerivation.deriveKey(master: master, usage: "Test", path: ["child"])
        XCTAssertEqual(key.count, 32)
    }

    func testDeriveKeyDeterministic() {
        let master = Data(repeating: 0x42, count: 32)
        let key1 = KeyDerivation.deriveKey(master: master, usage: "Happy EnCoder", path: ["content"])
        let key2 = KeyDerivation.deriveKey(master: master, usage: "Happy EnCoder", path: ["content"])
        XCTAssertEqual(key1, key2)
    }

    func testDeriveKeyDifferentPaths() {
        let master = Data(repeating: 0x42, count: 32)
        let key1 = KeyDerivation.deriveKey(master: master, usage: "Happy EnCoder", path: ["content"])
        let key2 = KeyDerivation.deriveKey(master: master, usage: "Happy Coder", path: ["analytics", "id"])
        XCTAssertNotEqual(key1, key2)
    }

    func testDeriveRootUsesCorrectHMACKey() {
        let seed = Data(repeating: 0xAA, count: 32)
        let state = KeyDerivation.deriveRoot(seed: seed, usage: "Happy EnCoder")
        XCTAssertEqual(state.key.count, 32)
        XCTAssertEqual(state.chainCode.count, 32)

        let expectedHMACKey = Data("Happy EnCoder Master Seed".utf8)
        let fullHash = KeyDerivation.hmacSHA512(key: expectedHMACKey, data: seed)
        XCTAssertEqual(state.key, fullHash.prefix(32))
        XCTAssertEqual(state.chainCode, fullHash.suffix(32))
    }

    func testDeriveChildPrependsZeroByte() {
        let chainCode = Data(repeating: 0xBB, count: 32)
        let state = KeyDerivation.deriveChild(chainCode: chainCode, index: "content")

        let expectedData = Data([0x00]) + Data("content".utf8)
        let fullHash = KeyDerivation.hmacSHA512(key: chainCode, data: expectedData)
        XCTAssertEqual(state.key, fullHash.prefix(32))
        XCTAssertEqual(state.chainCode, fullHash.suffix(32))
    }
}
