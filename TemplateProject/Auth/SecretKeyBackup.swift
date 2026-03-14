import Foundation

enum SecretKeyBackupError: Error {
    case invalidFormat
    case invalidKeyLength(got: Int, expected: Int)
    case noValidCharacters
}

enum SecretKeyBackup {

    private static let base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    // MARK: - Base32 (RFC 4648)

    static func bytesToBase32(_ data: Data) -> String {
        let alphabet = Array(base32Alphabet)
        var result = ""
        var buffer = 0
        var bufferLength = 0

        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bufferLength += 8

            while bufferLength >= 5 {
                bufferLength -= 5
                result.append(alphabet[(buffer >> bufferLength) & 0x1F])
            }
        }

        if bufferLength > 0 {
            result.append(alphabet[(buffer << (5 - bufferLength)) & 0x1F])
        }

        return result
    }

    static func base32ToBytes(_ base32: String) throws -> Data {
        let alphabet = base32Alphabet
        var normalized = base32.uppercased()
            .replacingOccurrences(of: "0", with: "O")
            .replacingOccurrences(of: "1", with: "I")
            .replacingOccurrences(of: "8", with: "B")
            .replacingOccurrences(of: "9", with: "G")

        let cleaned = normalized.filter { alphabet.contains($0) }

        guard !cleaned.isEmpty else {
            throw SecretKeyBackupError.noValidCharacters
        }

        var bytes = Data()
        var buffer = 0
        var bufferLength = 0

        for char in cleaned {
            guard let value = alphabet.firstIndex(of: char) else {
                throw SecretKeyBackupError.invalidFormat
            }
            let index = alphabet.distance(from: alphabet.startIndex, to: value)

            buffer = (buffer << 5) | index
            bufferLength += 5

            if bufferLength >= 8 {
                bufferLength -= 8
                bytes.append(UInt8((buffer >> bufferLength) & 0xFF))
            }
        }

        return bytes
    }

    // MARK: - Format / Parse

    static func formatForBackup(_ base64urlKey: String) -> String {
        let bytes = Base64Utils.decodeURL(base64urlKey)
        let base32 = bytesToBase32(bytes)

        var groups: [String] = []
        var i = base32.startIndex
        while i < base32.endIndex {
            let end = base32.index(i, offsetBy: 5, limitedBy: base32.endIndex) ?? base32.endIndex
            groups.append(String(base32[i..<end]))
            i = end
        }

        return groups.joined(separator: "-")
    }

    static func parseBackup(_ formatted: String) throws -> String {
        let bytes = try base32ToBytes(formatted)

        guard bytes.count == 32 else {
            throw SecretKeyBackupError.invalidKeyLength(got: bytes.count, expected: 32)
        }

        return Base64Utils.encodeURL(bytes)
    }

    static func isValid(_ key: String) -> Bool {
        if key.contains("-") || key.count > 50 {
            guard let parsed = try? parseBackup(key) else { return false }
            return Base64Utils.decodeURL(parsed).count == 32
        }
        return Base64Utils.decodeURL(key).count == 32
    }
}
