import Foundation

enum Base64Utils {

    // MARK: - Standard Base64

    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
    }

    static func decode(_ string: String) -> Data {
        Data(base64Encoded: string) ?? Data()
    }

    // MARK: - Base64URL (RFC 4648 §5, no padding)

    static func encodeURL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeURL(_ string: String) -> Data {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64) ?? Data()
    }
}
