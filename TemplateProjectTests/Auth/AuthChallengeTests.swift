import XCTest
@testable import TemplateProject

final class AuthChallengeTests: XCTestCase {

    func testChallengeProduces32ByteChallenge() {
        let secret = Data(repeating: 0x42, count: 32)
        let result = AuthChallenge.create(secret: secret)
        XCTAssertEqual(result.challenge.count, 32)
    }

    func testChallengeProduces64ByteSignature() {
        let secret = Data(repeating: 0x42, count: 32)
        let result = AuthChallenge.create(secret: secret)
        XCTAssertEqual(result.signature.count, 64)
    }

    func testChallengeProduces32BytePublicKey() {
        let secret = Data(repeating: 0x42, count: 32)
        let result = AuthChallenge.create(secret: secret)
        XCTAssertEqual(result.publicKey.count, 32)
    }

    func testSameSecretProducesSamePublicKey() {
        let secret = Data(repeating: 0x42, count: 32)
        let result1 = AuthChallenge.create(secret: secret)
        let result2 = AuthChallenge.create(secret: secret)
        XCTAssertEqual(result1.publicKey, result2.publicKey)
    }

    func testDifferentChallengesEachTime() {
        let secret = Data(repeating: 0x42, count: 32)
        let result1 = AuthChallenge.create(secret: secret)
        let result2 = AuthChallenge.create(secret: secret)
        XCTAssertNotEqual(result1.challenge, result2.challenge)
    }

    func testSignatureVerifies() {
        let secret = Data(repeating: 0xAA, count: 32)
        let result = AuthChallenge.create(secret: secret)
        let isValid = AuthChallenge.verify(
            signature: result.signature,
            message: result.challenge,
            publicKey: result.publicKey
        )
        XCTAssertTrue(isValid)
    }

    func testTamperedSignatureFails() {
        let secret = Data(repeating: 0xBB, count: 32)
        let result = AuthChallenge.create(secret: secret)
        var tampered = result.signature
        tampered[0] ^= 0xFF
        let isValid = AuthChallenge.verify(
            signature: tampered,
            message: result.challenge,
            publicKey: result.publicKey
        )
        XCTAssertFalse(isValid)
    }
}
