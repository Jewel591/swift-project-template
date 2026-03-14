import XCTest
@testable import TemplateProject

final class ServerConfigTests: XCTestCase {

    override func tearDown() {
        ServerConfig.setCustomURL(nil)
    }

    func testDefaultURL() {
        XCTAssertEqual(ServerConfig.serverURL, "https://api.cluster-fluster.com")
    }

    func testCustomURL() {
        ServerConfig.setCustomURL("https://my-server.example.com")
        XCTAssertEqual(ServerConfig.serverURL, "https://my-server.example.com")
    }

    func testClearCustomURL() {
        ServerConfig.setCustomURL("https://custom.example.com")
        ServerConfig.setCustomURL(nil)
        XCTAssertEqual(ServerConfig.serverURL, "https://api.cluster-fluster.com")
    }

    func testIsUsingCustomServer() {
        XCTAssertFalse(ServerConfig.isUsingCustomServer)
        ServerConfig.setCustomURL("https://custom.example.com")
        XCTAssertTrue(ServerConfig.isUsingCustomServer)
    }

    func testValidateURL() {
        XCTAssertTrue(ServerConfig.validate("https://example.com").isValid)
        XCTAssertTrue(ServerConfig.validate("http://localhost:3000").isValid)
        XCTAssertFalse(ServerConfig.validate("not-a-url").isValid)
        XCTAssertFalse(ServerConfig.validate("").isValid)
        XCTAssertFalse(ServerConfig.validate("ftp://files.com").isValid)
    }

    func testTrimsWhitespace() {
        ServerConfig.setCustomURL("  https://trimmed.com  ")
        XCTAssertEqual(ServerConfig.serverURL, "https://trimmed.com")
    }
}
