import Foundation
import CryptoKit

struct KeyTreeState {
    let key: Data       // 32 bytes
    let chainCode: Data // 32 bytes
}

enum KeyDerivation {

    /// Standard HMAC-SHA512 (RFC 2104)
    static func hmacSHA512(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA512>.authenticationCode(for: data, using: symmetricKey)
        return Data(mac)
    }

    /// Derive root state from seed and usage string.
    /// Mirrors: deriveSecretKeyTreeRoot(seed, usage)
    /// HMAC key = UTF8(usage + " Master Seed"), HMAC data = seed
    static func deriveRoot(seed: Data, usage: String) -> KeyTreeState {
        let hmacKey = Data((usage + " Master Seed").utf8)
        let hash = hmacSHA512(key: hmacKey, data: seed)
        return KeyTreeState(
            key: hash.prefix(32),
            chainCode: hash.suffix(32)
        )
    }

    /// Derive child state from parent chain code and index string.
    /// Mirrors: deriveSecretKeyTreeChild(chainCode, index)
    /// HMAC key = chainCode, HMAC data = [0x00 || UTF8(index)]
    static func deriveChild(chainCode: Data, index: String) -> KeyTreeState {
        let data = Data([0x00]) + Data(index.utf8)
        let hash = hmacSHA512(key: chainCode, data: data)
        return KeyTreeState(
            key: hash.prefix(32),
            chainCode: hash.suffix(32)
        )
    }

    /// Derive a key by walking a path from master secret.
    /// Mirrors: deriveKey(master, usage, path[])
    static func deriveKey(master: Data, usage: String, path: [String]) -> Data {
        var state = deriveRoot(seed: master, usage: usage)
        for index in path {
            state = deriveChild(chainCode: state.chainCode, index: index)
        }
        return state.key
    }
}
