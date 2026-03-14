import Foundation

enum HappyAPIError: Error {
    case invalidURL
    case httpError(statusCode: Int, data: Data?)
    case decodingFailed
    case networkError(Error)
}

enum HappyAPIClient {

    // MARK: - Auth Endpoints

    static func buildAuthRequest(challenge: Data, signature: Data, publicKey: Data) -> URLRequest {
        let body: [String: String] = [
            "challenge": Base64Utils.encode(challenge),
            "signature": Base64Utils.encode(signature),
            "publicKey": Base64Utils.encode(publicKey),
        ]
        return jsonPost(path: "/v1/auth", body: body)
    }

    static func buildAccountRequest(publicKey: Data) -> URLRequest {
        let body = ["publicKey": Base64Utils.encode(publicKey)]
        return jsonPost(path: "/v1/auth/account/request", body: body)
    }

    static func buildAccountResponse(token: String, publicKey: Data, response: Data) -> URLRequest {
        let body: [String: String] = [
            "publicKey": Base64Utils.encode(publicKey),
            "response": Base64Utils.encode(response),
        ]
        var request = jsonPost(path: "/v1/auth/account/response", body: body)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Execute

    static func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw HappyAPIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    static func executeVoid(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw HappyAPIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    // MARK: - Helpers

    private static func jsonPost(path: String, body: [String: String]) -> URLRequest {
        let url = URL(string: ServerConfig.serverURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}
