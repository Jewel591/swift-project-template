import Testing
@testable import TemplateProject

@Suite("HappyAPIClient Tests")
struct HappyAPIClientTests {

    @Test("Auth request has correct URL and method")
    func authRequestURL() {
        let challenge = Data(repeating: 0xAA, count: 32)
        let signature = Data(repeating: 0xBB, count: 64)
        let publicKey = Data(repeating: 0xCC, count: 32)

        let request = HappyAPIClient.buildAuthRequest(
            challenge: challenge,
            signature: signature,
            publicKey: publicKey
        )

        #expect(request.url?.path == "/v1/auth")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("Auth request body contains base64 encoded fields")
    func authRequestBody() throws {
        let challenge = Data(repeating: 0xAA, count: 32)
        let signature = Data(repeating: 0xBB, count: 64)
        let publicKey = Data(repeating: 0xCC, count: 32)

        let request = HappyAPIClient.buildAuthRequest(
            challenge: challenge,
            signature: signature,
            publicKey: publicKey
        )

        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
        let dict = try #require(json)

        #expect(dict["challenge"] == Base64Utils.encode(challenge))
        #expect(dict["signature"] == Base64Utils.encode(signature))
        #expect(dict["publicKey"] == Base64Utils.encode(publicKey))
    }

    @Test("Account request has correct endpoint")
    func accountRequestURL() {
        let publicKey = Data(repeating: 0xDD, count: 32)
        let request = HappyAPIClient.buildAccountRequest(publicKey: publicKey)

        #expect(request.url?.path == "/v1/auth/account/request")
        #expect(request.httpMethod == "POST")
    }

    @Test("Account response includes bearer token")
    func accountResponseAuth() {
        let publicKey = Data(repeating: 0xEE, count: 32)
        let response = Data(repeating: 0xFF, count: 64)
        let token = "test-bearer-token"

        let request = HappyAPIClient.buildAccountResponse(
            token: token,
            publicKey: publicKey,
            response: response
        )

        #expect(request.url?.path == "/v1/auth/account/response")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-bearer-token")
    }

    @Test("Request uses configured server URL")
    func usesServerConfig() {
        let request = HappyAPIClient.buildAccountRequest(
            publicKey: Data(repeating: 0x00, count: 32)
        )

        #expect(request.url?.absoluteString.hasPrefix(ServerConfig.serverURL) == true)
    }
}
