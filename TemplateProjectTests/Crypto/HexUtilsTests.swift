import XCTest
@testable import TemplateProject

final class HexUtilsTests: XCTestCase {

    func testEncodeHex() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(HexUtils.encode(data), "deadbeef")
    }

    func testDecodeHex() {
        let data = HexUtils.decode("deadbeef")
        XCTAssertEqual(data, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testRoundTrip() {
        let data = Data(repeating: 0xAB, count: 32)
        XCTAssertEqual(HexUtils.decode(HexUtils.encode(data)), data)
    }

    func testEmpty() {
        XCTAssertEqual(HexUtils.encode(Data()), "")
        XCTAssertEqual(HexUtils.decode(""), Data())
    }

    func testLowercaseOutput() {
        let data = Data([0xFF])
        XCTAssertEqual(HexUtils.encode(data), "ff")
    }
}
