import XCTest
@testable import TemplateProject

final class Base64UtilsTests: XCTestCase {

    func testEncodeDecodeBase64() {
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])
        let encoded = Base64Utils.encode(data)
        XCTAssertEqual(encoded, "SGVsbG8=")
        let decoded = Base64Utils.decode(encoded)
        XCTAssertEqual(decoded, data)
    }

    func testEncodeDecodeBase64URL() {
        let data = Data([0xfb, 0xff, 0xfe])
        let encoded = Base64Utils.encodeURL(data)
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        let decoded = Base64Utils.decodeURL(encoded)
        XCTAssertEqual(decoded, data)
    }

    func testRoundTrip32Bytes() {
        let data = Data(repeating: 0xAB, count: 32)
        XCTAssertEqual(Base64Utils.decode(Base64Utils.encode(data)), data)
        XCTAssertEqual(Base64Utils.decodeURL(Base64Utils.encodeURL(data)), data)
    }

    func testEmptyData() {
        let data = Data()
        XCTAssertEqual(Base64Utils.encode(data), "")
        XCTAssertEqual(Base64Utils.decode(""), data)
    }
}
