import XCTest
@testable import TemplateProject

final class CredentialStoreTests: XCTestCase {

    override func setUp() async throws {
        await CredentialStore.removeCredentials()
    }

    override func tearDown() async throws {
        await CredentialStore.removeCredentials()
    }

    func testStoreAndRetrieveCredentials() async throws {
        let creds = AuthCredentials(token: "test-token-123", secret: "base64url-secret")
        try await CredentialStore.setCredentials(creds)

        let retrieved = try await CredentialStore.getCredentials()
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.token, "test-token-123")
        XCTAssertEqual(retrieved?.secret, "base64url-secret")
    }

    func testRemoveCredentials() async throws {
        let creds = AuthCredentials(token: "token", secret: "secret")
        try await CredentialStore.setCredentials(creds)
        await CredentialStore.removeCredentials()

        let retrieved = try await CredentialStore.getCredentials()
        XCTAssertNil(retrieved)
    }

    func testNoCredentialsReturnsNil() async throws {
        let retrieved = try await CredentialStore.getCredentials()
        XCTAssertNil(retrieved)
    }

    func testOverwriteCredentials() async throws {
        let creds1 = AuthCredentials(token: "old-token", secret: "old-secret")
        try await CredentialStore.setCredentials(creds1)

        let creds2 = AuthCredentials(token: "new-token", secret: "new-secret")
        try await CredentialStore.setCredentials(creds2)

        let retrieved = try await CredentialStore.getCredentials()
        XCTAssertEqual(retrieved?.token, "new-token")
    }
}
