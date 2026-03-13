# Phase 1: Crypto Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement the cryptographic primitives layer that mirrors `happy-app/sources/encryption/`, fully tested via CI.

**Architecture:** Bottom-up — pure functions with no UI or network dependencies. Each module is independently testable. Swift CryptoKit handles HMAC-SHA512 and AES-256-GCM natively; swift-sodium handles NaCl operations (SecretBox, Box, Sign seed keypairs).

**Tech Stack:** Swift 6, CryptoKit, swift-sodium (SPM), XCTest

**Reference:** `docs/TECHNICAL_RESEARCH.md` sections 1.1–1.6, source files in `/tmp/happy/packages/happy-app/sources/encryption/`

---

### Task 0: Project Setup — Remove template packages, lower deployment target, add swift-sodium

**Files:**
- Modify: `Talon.xcodeproj/project.pbxproj`
- Modify: `TemplateProject/TemplateProjectApp.swift`
- Modify: `.github/workflows/build.yml`

**Step 1: Remove all 5 SPM package references and product dependencies from pbxproj**

Remove from pbxproj:
- All `XCRemoteSwiftPackageReference` entries (LayoutUIKit, BrandKit, SupabaseKit, RevenueCatKit, PromoKit)
- All `XCSwiftPackageProductDependency` entries
- All `PBXBuildFile` entries referencing these packages
- All `packageProductDependencies` arrays in targets
- All `packageReferences` in the project object

**Step 2: Clean up TemplateProjectApp.swift**

Remove `@_exported import LayoutUIKit` and `@_exported import BrandKit`. Keep it as a minimal SwiftUI app entry point.

**Step 3: Lower deployment targets in pbxproj**

Change ALL build configurations (Debug + Release for all 3 targets + project):
- `IPHONEOS_DEPLOYMENT_TARGET` = `18.0`
- `MACOSX_DEPLOYMENT_TARGET` = `15.0`
- `XROS_DEPLOYMENT_TARGET` = `2.0`

**Step 4: Add swift-sodium SPM dependency**

Add to pbxproj:
- `XCRemoteSwiftPackageReference` for `https://github.com/jedisct1/swift-sodium` (branch: master)
- `XCSwiftPackageProductDependency` for `Sodium` in the main target
- `PBXBuildFile` for `Sodium in Frameworks`

**Step 5: Update CI workflow to use Xcode 16.2 and run tests**

Update `.github/workflows/build.yml`:
- Hardcode `sudo xcode-select -s /Applications/Xcode_16.2.app/Contents/Developer`
- Remove the Xcode version compatibility check (no longer needed)
- Add a test job that runs `xcodebuild test`
- Use `platform=iOS Simulator,name=iPhone 16,OS=18.2`

**Step 6: Commit**

```
git add -A
git commit -m "chore: remove template packages, lower deployment target to iOS 18, add swift-sodium"
```

---

### Task 1: Base64Utils — Base64 / Base64URL encoding

**Files:**
- Create: `TemplateProject/Crypto/Base64Utils.swift`
- Test: `TemplateProjectTests/Crypto/Base64UtilsTests.swift`

Mirrors: `happy-app/sources/encryption/base64.ts`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import TemplateProject

final class Base64UtilsTests: XCTestCase {

    // Standard Base64 round-trip
    func testEncodeDecodeBase64() {
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello"
        let encoded = Base64Utils.encode(data)
        XCTAssertEqual(encoded, "SGVsbG8=")
        let decoded = Base64Utils.decode(encoded)
        XCTAssertEqual(decoded, data)
    }

    // Base64URL round-trip (no padding, URL-safe chars)
    func testEncodeDecodeBase64URL() {
        // Bytes that produce + and / in standard base64
        let data = Data([0xfb, 0xff, 0xfe])
        let encoded = Base64Utils.encodeURL(data)
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        let decoded = Base64Utils.decodeURL(encoded)
        XCTAssertEqual(decoded, data)
    }

    // 32-byte key round-trip (common case for encryption keys)
    func testRoundTrip32Bytes() {
        let data = Data(repeating: 0xAB, count: 32)
        XCTAssertEqual(Base64Utils.decode(Base64Utils.encode(data)), data)
        XCTAssertEqual(Base64Utils.decodeURL(Base64Utils.encodeURL(data)), data)
    }

    // Empty data
    func testEmptyData() {
        let data = Data()
        XCTAssertEqual(Base64Utils.encode(data), "")
        XCTAssertEqual(Base64Utils.decode(""), data)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Talon.xcodeproj -scheme Talon -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2' -only-testing:TalonTests/Base64UtilsTests`
Expected: FAIL — `Base64Utils` not defined

**Step 3: Write minimal implementation**

```swift
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
```

**Step 4: Run test to verify it passes**

Run: same command as Step 2
Expected: PASS

**Step 5: Commit**

```
git add TemplateProject/Crypto/Base64Utils.swift TemplateProjectTests/Crypto/Base64UtilsTests.swift
git commit -m "feat(crypto): add Base64/Base64URL encoding utilities"
```

---

### Task 2: HexUtils — Hex encoding

**Files:**
- Create: `TemplateProject/Crypto/HexUtils.swift`
- Test: `TemplateProjectTests/Crypto/HexUtilsTests.swift`

Mirrors: `happy-app/sources/encryption/hex.ts`

**Step 1: Write the failing tests**

```swift
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

    // Happy uses hex.encode which returns lowercase
    func testLowercaseOutput() {
        let data = Data([0xFF])
        XCTAssertEqual(HexUtils.encode(data), "ff")
    }
}
```

**Step 2: Run test to verify it fails**

Expected: FAIL — `HexUtils` not defined

**Step 3: Write minimal implementation**

```swift
import Foundation

enum HexUtils {

    static func encode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func decode(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        return data
    }
}
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```
git commit -m "feat(crypto): add hex encoding utilities"
```

---

### Task 3: KeyDerivation — HMAC-SHA512 key derivation tree

**Files:**
- Create: `TemplateProject/Crypto/KeyDerivation.swift`
- Test: `TemplateProjectTests/Crypto/KeyDerivationTests.swift`

Mirrors: `happy-app/sources/encryption/deriveKey.ts` + `hmac_sha512.ts`

**Step 1: Write the failing tests**

```swift
import XCTest
import CryptoKit
@testable import TemplateProject

final class KeyDerivationTests: XCTestCase {

    // HMAC-SHA512 produces 64 bytes
    func testHMACSHA512OutputLength() {
        let key = Data(repeating: 0x0B, count: 20)
        let data = Data("Hi There".utf8)
        let result = KeyDerivation.hmacSHA512(key: key, data: data)
        XCTAssertEqual(result.count, 64)
    }

    // RFC 4231 test vector 1
    func testHMACSHA512RFC4231Vector1() {
        let key = Data(repeating: 0x0B, count: 20)
        let data = Data("Hi There".utf8)
        let result = KeyDerivation.hmacSHA512(key: key, data: data)
        let hex = HexUtils.encode(result)
        XCTAssertEqual(hex, "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854")
    }

    // deriveKey produces 32-byte key
    func testDeriveKeyOutputLength() {
        let master = Data(repeating: 0x01, count: 32)
        let key = KeyDerivation.deriveKey(master: master, usage: "Test", path: ["child"])
        XCTAssertEqual(key.count, 32)
    }

    // Same inputs produce same outputs (deterministic)
    func testDeriveKeyDeterministic() {
        let master = Data(repeating: 0x42, count: 32)
        let key1 = KeyDerivation.deriveKey(master: master, usage: "Happy EnCoder", path: ["content"])
        let key2 = KeyDerivation.deriveKey(master: master, usage: "Happy EnCoder", path: ["content"])
        XCTAssertEqual(key1, key2)
    }

    // Different paths produce different keys
    func testDeriveKeyDifferentPaths() {
        let master = Data(repeating: 0x42, count: 32)
        let key1 = KeyDerivation.deriveKey(master: master, usage: "Happy EnCoder", path: ["content"])
        let key2 = KeyDerivation.deriveKey(master: master, usage: "Happy Coder", path: ["analytics", "id"])
        XCTAssertNotEqual(key1, key2)
    }

    // Root derivation: HMAC-SHA512(key=usage+" Master Seed", data=seed)
    func testDeriveRootUsesCorrectHMACKey() {
        let seed = Data(repeating: 0xAA, count: 32)
        let state = KeyDerivation.deriveRoot(seed: seed, usage: "Happy EnCoder")
        XCTAssertEqual(state.key.count, 32)
        XCTAssertEqual(state.chainCode.count, 32)

        // Manually verify: HMAC key should be UTF8("Happy EnCoder Master Seed")
        let expectedHMACKey = Data("Happy EnCoder Master Seed".utf8)
        let fullHash = KeyDerivation.hmacSHA512(key: expectedHMACKey, data: seed)
        XCTAssertEqual(state.key, fullHash.prefix(32))
        XCTAssertEqual(state.chainCode, fullHash.suffix(32))
    }

    // Child derivation: data = [0x00 || UTF8(index)]
    func testDeriveChildPrependsZeroByte() {
        let chainCode = Data(repeating: 0xBB, count: 32)
        let state = KeyDerivation.deriveChild(chainCode: chainCode, index: "content")

        let expectedData = Data([0x00]) + Data("content".utf8)
        let fullHash = KeyDerivation.hmacSHA512(key: chainCode, data: expectedData)
        XCTAssertEqual(state.key, fullHash.prefix(32))
        XCTAssertEqual(state.chainCode, fullHash.suffix(32))
    }
}
```

**Step 2: Run test to verify it fails**

Expected: FAIL — `KeyDerivation` not defined

**Step 3: Write minimal implementation**

```swift
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
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```
git commit -m "feat(crypto): add HMAC-SHA512 key derivation tree"
```

---

### Task 4: AESGCMCrypto — AES-256-GCM encrypt/decrypt

**Files:**
- Create: `TemplateProject/Crypto/AESGCMCrypto.swift`
- Test: `TemplateProjectTests/Crypto/AESGCMCryptoTests.swift`

Mirrors: `happy-app/sources/encryption/aes.ts` + AES256Encryption in `encryptor.ts` lines 81-126

Binary layout: `[version(1) | nonce(12) | ciphertext | authTag(16)]`
Version byte is always `0x00`.

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import TemplateProject

final class AESGCMCryptoTests: XCTestCase {

    func testEncryptDecryptRoundTrip() throws {
        let key = Data(repeating: 0xAA, count: 32)
        let plaintext = ["hello": "world"]
        let encrypted = try AESGCMCrypto.encrypt(plaintext, key: key)
        let decrypted: [String: String] = try AESGCMCrypto.decrypt(encrypted, key: key)
        XCTAssertEqual(decrypted["hello"], "world")
    }

    // Version byte must be 0x00
    func testEncryptedDataStartsWithVersionByte() throws {
        let key = Data(repeating: 0xBB, count: 32)
        let encrypted = try AESGCMCrypto.encrypt(["key": "value"], key: key)
        XCTAssertEqual(encrypted[0], 0x00)
    }

    // Minimum size: version(1) + nonce(12) + authTag(16) = 29 + ciphertext
    func testEncryptedMinimumSize() throws {
        let key = Data(repeating: 0xCC, count: 32)
        let encrypted = try AESGCMCrypto.encrypt(["a": 1], key: key)
        XCTAssertGreaterThanOrEqual(encrypted.count, 29)
    }

    // Wrong key should fail
    func testDecryptWithWrongKeyFails() throws {
        let key1 = Data(repeating: 0x01, count: 32)
        let key2 = Data(repeating: 0x02, count: 32)
        let encrypted = try AESGCMCrypto.encrypt(["secret": true], key: key1)
        XCTAssertThrowsError(try AESGCMCrypto.decrypt(encrypted, key: key2) as [String: Bool])
    }

    // Wrong version byte should fail
    func testDecryptWithWrongVersionFails() throws {
        let key = Data(repeating: 0xDD, count: 32)
        var encrypted = try AESGCMCrypto.encrypt(["x": 1], key: key)
        encrypted[0] = 0x01  // Corrupt version
        XCTAssertThrowsError(try AESGCMCrypto.decrypt(encrypted, key: key) as [String: Int])
    }

    // Nested JSON object
    func testNestedJSON() throws {
        let key = Data(repeating: 0xEE, count: 32)
        let original: [String: Any] = ["role": "session", "content": ["t": "text", "text": "hello"]]
        // Use Codable struct instead
        let msg = TestMessage(role: "session", text: "hello")
        let encrypted = try AESGCMCrypto.encrypt(msg, key: key)
        let decrypted: TestMessage = try AESGCMCrypto.decrypt(encrypted, key: key)
        XCTAssertEqual(decrypted.role, "session")
        XCTAssertEqual(decrypted.text, "hello")
    }
}

private struct TestMessage: Codable, Equatable {
    let role: String
    let text: String
}
```

**Step 2: Run test to verify it fails**

Expected: FAIL — `AESGCMCrypto` not defined

**Step 3: Write minimal implementation**

```swift
import Foundation
import CryptoKit

enum AESGCMCryptoError: Error {
    case invalidVersion
    case dataTooShort
    case decryptionFailed
    case serializationFailed
}

enum AESGCMCrypto {

    /// Encrypt a Codable value to: [version(1) | nonce(12) | ciphertext | authTag(16)]
    /// Mirrors: AES256Encryption.encrypt() in encryptor.ts
    static func encrypt<T: Encodable>(_ value: T, key: Data) throws -> Data {
        let json = try JSONEncoder().encode(value)
        let symmetricKey = SymmetricKey(data: key)
        let sealedBox = try AES.GCM.seal(json, using: symmetricKey)

        // Layout: [version(1) | nonce(12) | ciphertext | tag(16)]
        var result = Data([0x00])                    // version byte
        result.append(sealedBox.nonce.withUnsafeBytes { Data($0) })  // 12 bytes
        result.append(sealedBox.ciphertext)          // variable
        result.append(sealedBox.tag)                 // 16 bytes
        return result
    }

    /// Decrypt data back to a Codable value.
    /// Mirrors: AES256Encryption.decrypt() in encryptor.ts
    static func decrypt<T: Decodable>(_ data: Data, key: Data) throws -> T {
        // Minimum: version(1) + nonce(12) + tag(16) = 29
        guard data.count >= 29 else { throw AESGCMCryptoError.dataTooShort }
        guard data[0] == 0x00 else { throw AESGCMCryptoError.invalidVersion }

        let nonce = try AES.GCM.Nonce(data: data[1..<13])
        let ciphertext = data[13..<(data.count - 16)]
        let tag = data[(data.count - 16)...]

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let symmetricKey = SymmetricKey(data: key)
        let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)

        return try JSONDecoder().decode(T.self, from: plaintext)
    }
}
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```
git commit -m "feat(crypto): add AES-256-GCM encrypt/decrypt"
```

---

### Task 5: SecretBoxCrypto — NaCl XSalsa20-Poly1305

**Files:**
- Create: `TemplateProject/Crypto/SecretBoxCrypto.swift`
- Test: `TemplateProjectTests/Crypto/SecretBoxCryptoTests.swift`

Mirrors: `happy-app/sources/encryption/libsodium.ts` lines 36-57 (encryptSecretBox / decryptSecretBox)

Binary layout: `[nonce(24) | ciphertext+poly1305_tag]`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import TemplateProject

final class SecretBoxCryptoTests: XCTestCase {

    func testEncryptDecryptRoundTrip() throws {
        let key = Data(repeating: 0xAA, count: 32)
        let original = ["message": "hello world"]
        let encrypted = try SecretBoxCrypto.encrypt(original, key: key)
        let decrypted: [String: String] = try SecretBoxCrypto.decrypt(encrypted, key: key)
        XCTAssertEqual(decrypted["message"], "hello world")
    }

    // Nonce is 24 bytes, so encrypted data starts with 24-byte nonce
    func testEncryptedStartsWithNonce() throws {
        let key = Data(repeating: 0xBB, count: 32)
        let encrypted = try SecretBoxCrypto.encrypt(["x": 1], key: key)
        // Minimum: nonce(24) + poly1305_tag(16) + at least 1 byte ciphertext
        XCTAssertGreaterThanOrEqual(encrypted.count, 41)
    }

    // Two encryptions of same data should differ (random nonce)
    func testNonceIsRandom() throws {
        let key = Data(repeating: 0xCC, count: 32)
        let data = ["same": "data"]
        let enc1 = try SecretBoxCrypto.encrypt(data, key: key)
        let enc2 = try SecretBoxCrypto.encrypt(data, key: key)
        XCTAssertNotEqual(enc1, enc2) // Different nonces
    }

    // Wrong key should return nil
    func testDecryptWithWrongKeyReturnsNil() throws {
        let key1 = Data(repeating: 0x01, count: 32)
        let key2 = Data(repeating: 0x02, count: 32)
        let encrypted = try SecretBoxCrypto.encrypt(["secret": true], key: key1)
        let result: [String: Bool]? = SecretBoxCrypto.decryptOrNil(encrypted, key: key2)
        XCTAssertNil(result)
    }
}
```

**Step 2: Run test to verify it fails**

Expected: FAIL — `SecretBoxCrypto` not defined

**Step 3: Write minimal implementation**

```swift
import Foundation
import Sodium

enum SecretBoxCryptoError: Error {
    case encryptionFailed
    case decryptionFailed
    case serializationFailed
}

enum SecretBoxCrypto {

    private static let sodium = Sodium()

    /// Encrypt a Codable value to: [nonce(24) | ciphertext+tag]
    /// Mirrors: encryptSecretBox() in libsodium.ts
    static func encrypt<T: Encodable>(_ value: T, key: Data) throws -> Data {
        let json = try JSONEncoder().encode(value)
        let keyBytes = Bytes(key)

        guard let encrypted: Bytes = sodium.secretBox.seal(
            message: Bytes(json),
            secretKey: keyBytes
        ) else {
            throw SecretBoxCryptoError.encryptionFailed
        }

        // sodium.secretBox.seal already returns [nonce(24) | ciphertext+tag]
        return Data(encrypted)
    }

    /// Decrypt data back to a Codable value. Throws on failure.
    /// Mirrors: decryptSecretBox() in libsodium.ts
    static func decrypt<T: Decodable>(_ data: Data, key: Data) throws -> T {
        let keyBytes = Bytes(key)

        guard let decrypted = sodium.secretBox.open(
            nonceAndAuthenticatedCipherText: Bytes(data),
            secretKey: keyBytes
        ) else {
            throw SecretBoxCryptoError.decryptionFailed
        }

        return try JSONDecoder().decode(T.self, from: Data(decrypted))
    }

    /// Decrypt, returning nil on failure instead of throwing.
    static func decryptOrNil<T: Decodable>(_ data: Data, key: Data) -> T? {
        try? decrypt(data, key: key)
    }
}
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```
git commit -m "feat(crypto): add NaCl SecretBox (XSalsa20-Poly1305) encrypt/decrypt"
```

---

### Task 6: BoxCrypto — NaCl asymmetric Box encryption

**Files:**
- Create: `TemplateProject/Crypto/BoxCrypto.swift`
- Test: `TemplateProjectTests/Crypto/BoxCryptoTests.swift`

Mirrors: `happy-app/sources/encryption/libsodium.ts` lines 8-34 (encryptBox / decryptBox)

Binary layout: `[ephemeralPublicKey(32) | nonce(24) | ciphertext+tag]`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import TemplateProject

final class BoxCryptoTests: XCTestCase {

    func testEncryptDecryptRoundTrip() throws {
        let keyPair = BoxCrypto.generateKeyPairFromSeed(Data(repeating: 0xAA, count: 32))
        let plaintext = Data("hello world".utf8)
        let encrypted = try BoxCrypto.encrypt(plaintext, recipientPublicKey: keyPair.publicKey)
        let decrypted = try BoxCrypto.decrypt(encrypted, recipientSecretKey: keyPair.secretKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    // Layout: ephemeral_pk(32) + nonce(24) + ciphertext + tag(16)
    func testEncryptedLayout() throws {
        let keyPair = BoxCrypto.generateKeyPairFromSeed(Data(repeating: 0xBB, count: 32))
        let plaintext = Data("test".utf8)
        let encrypted = try BoxCrypto.encrypt(plaintext, recipientPublicKey: keyPair.publicKey)
        // Minimum: 32 + 24 + len("test") + 16 = 76
        XCTAssertGreaterThanOrEqual(encrypted.count, 76)
    }

    // Ephemeral key is random — two encryptions differ
    func testEphemeralKeyIsRandom() throws {
        let keyPair = BoxCrypto.generateKeyPairFromSeed(Data(repeating: 0xCC, count: 32))
        let plaintext = Data("same".utf8)
        let enc1 = try BoxCrypto.encrypt(plaintext, recipientPublicKey: keyPair.publicKey)
        let enc2 = try BoxCrypto.encrypt(plaintext, recipientPublicKey: keyPair.publicKey)
        // First 32 bytes (ephemeral pk) should differ
        XCTAssertNotEqual(Data(enc1.prefix(32)), Data(enc2.prefix(32)))
    }

    // Wrong secret key should fail
    func testDecryptWithWrongKeyFails() throws {
        let kp1 = BoxCrypto.generateKeyPairFromSeed(Data(repeating: 0x01, count: 32))
        let kp2 = BoxCrypto.generateKeyPairFromSeed(Data(repeating: 0x02, count: 32))
        let encrypted = try BoxCrypto.encrypt(Data("secret".utf8), recipientPublicKey: kp1.publicKey)
        XCTAssertNil(BoxCrypto.decryptOrNil(encrypted, recipientSecretKey: kp2.secretKey))
    }

    // Seed-based keypair is deterministic
    func testSeedKeyPairDeterministic() {
        let seed = Data(repeating: 0xDD, count: 32)
        let kp1 = BoxCrypto.generateKeyPairFromSeed(seed)
        let kp2 = BoxCrypto.generateKeyPairFromSeed(seed)
        XCTAssertEqual(kp1.publicKey, kp2.publicKey)
        XCTAssertEqual(kp1.secretKey, kp2.secretKey)
    }
}
```

**Step 2: Run test to verify it fails**

Expected: FAIL — `BoxCrypto` not defined

**Step 3: Write minimal implementation**

```swift
import Foundation
import Sodium

struct BoxKeyPair {
    let publicKey: Data   // 32 bytes
    let secretKey: Data   // 32 bytes
}

enum BoxCryptoError: Error {
    case encryptionFailed
    case decryptionFailed
    case invalidBundle
}

enum BoxCrypto {

    private static let sodium = Sodium()

    /// Generate X25519 keypair from 32-byte seed.
    /// Mirrors: sodium.crypto_box_seed_keypair(seed) in libsodium.ts
    static func generateKeyPairFromSeed(_ seed: Data) -> BoxKeyPair {
        let kp = sodium.box.keyPair(seed: Bytes(seed))!
        return BoxKeyPair(publicKey: Data(kp.publicKey), secretKey: Data(kp.secretKey))
    }

    /// Encrypt data with ephemeral keypair.
    /// Output: [ephemeralPublicKey(32) | nonce(24) | ciphertext+tag]
    /// Mirrors: encryptBox() in libsodium.ts
    static func encrypt(_ data: Data, recipientPublicKey: Data) throws -> Data {
        let ephemeralKP = sodium.box.keyPair()!
        let nonce = sodium.box.nonce()

        guard let encrypted = sodium.box.seal(
            message: Bytes(data),
            recipientPublicKey: Bytes(recipientPublicKey),
            senderSecretKey: ephemeralKP.secretKey,
            nonce: nonce
        ) else {
            throw BoxCryptoError.encryptionFailed
        }

        var result = Data(ephemeralKP.publicKey)  // 32 bytes
        result.append(Data(nonce))                // 24 bytes
        result.append(Data(encrypted))            // ciphertext + tag
        return result
    }

    /// Decrypt data encrypted with encrypt().
    /// Mirrors: decryptBox() in libsodium.ts
    static func decrypt(_ bundle: Data, recipientSecretKey: Data) throws -> Data {
        // Minimum: ephemeral_pk(32) + nonce(24) + tag(16) = 72
        guard bundle.count >= 72 else { throw BoxCryptoError.invalidBundle }

        let ephemeralPK = Bytes(bundle[0..<32])
        let nonce = Bytes(bundle[32..<56])
        let ciphertext = Bytes(bundle[56...])

        guard let decrypted = sodium.box.open(
            authenticatedCipherText: ciphertext,
            senderPublicKey: ephemeralPK,
            recipientSecretKey: Bytes(recipientSecretKey),
            nonce: nonce
        ) else {
            throw BoxCryptoError.decryptionFailed
        }

        return Data(decrypted)
    }

    /// Decrypt, returning nil on failure.
    static func decryptOrNil(_ bundle: Data, recipientSecretKey: Data) -> Data? {
        try? decrypt(bundle, recipientSecretKey: recipientSecretKey)
    }
}
```

**Step 4: Run test to verify it passes**

Expected: PASS

**Step 5: Commit**

```
git commit -m "feat(crypto): add NaCl Box (X25519 + XSalsa20) asymmetric encrypt/decrypt"
```

---

### Task 7: Integration test — Full encryption key hierarchy

**Files:**
- Test: `TemplateProjectTests/Crypto/EncryptionIntegrationTests.swift`

Verifies the complete key derivation chain used by Happy:
`masterSecret → deriveKey → contentDataKey → BoxKeyPair → encrypt/decrypt DEK`

**Step 1: Write the integration test**

```swift
import XCTest
@testable import TemplateProject

final class EncryptionIntegrationTests: XCTestCase {

    /// Test the full Happy encryption key hierarchy:
    /// masterSecret → contentDataKey → contentKeyPair → DEK encrypt/decrypt
    func testFullKeyHierarchy() throws {
        // 1. Simulate a 32-byte master secret (received from QR auth)
        let masterSecret = Data(repeating: 0x42, count: 32)

        // 2. Derive content data key (mirrors Encryption.create() in encryption.ts)
        let contentDataKey = KeyDerivation.deriveKey(
            master: masterSecret,
            usage: "Happy EnCoder",
            path: ["content"]
        )
        XCTAssertEqual(contentDataKey.count, 32)

        // 3. Generate content keypair from contentDataKey
        let contentKeyPair = BoxCrypto.generateKeyPairFromSeed(contentDataKey)
        XCTAssertEqual(contentKeyPair.publicKey.count, 32)
        XCTAssertEqual(contentKeyPair.secretKey.count, 32)

        // 4. Generate a session-specific DEK (data encryption key)
        let sessionDEK = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        // 5. Wrap (encrypt) DEK: [0x00 | encryptBox(DEK, contentKeyPair.publicKey)]
        let encryptedDEK_inner = try BoxCrypto.encrypt(sessionDEK, recipientPublicKey: contentKeyPair.publicKey)
        var wrappedDEK = Data([0x00])
        wrappedDEK.append(encryptedDEK_inner)

        // 6. Unwrap (decrypt) DEK
        XCTAssertEqual(wrappedDEK[0], 0x00)
        let unwrappedDEK = try BoxCrypto.decrypt(Data(wrappedDEK[1...]), recipientSecretKey: contentKeyPair.secretKey)
        XCTAssertEqual(unwrappedDEK, sessionDEK)

        // 7. Use DEK to encrypt/decrypt a message with AES-GCM
        let message = TestSessionMessage(role: "session", text: "Hello from Swift!")
        let encrypted = try AESGCMCrypto.encrypt(message, key: unwrappedDEK)
        let decrypted: TestSessionMessage = try AESGCMCrypto.decrypt(encrypted, key: unwrappedDEK)
        XCTAssertEqual(decrypted.role, "session")
        XCTAssertEqual(decrypted.text, "Hello from Swift!")

        // 8. Also test legacy path: SecretBox with masterSecret directly
        let legacyEncrypted = try SecretBoxCrypto.encrypt(message, key: masterSecret)
        let legacyDecrypted: TestSessionMessage = try SecretBoxCrypto.decrypt(legacyEncrypted, key: masterSecret)
        XCTAssertEqual(legacyDecrypted.text, "Hello from Swift!")

        // 9. Derive anon ID (mirrors encryption.ts)
        let anonIDKey = KeyDerivation.deriveKey(
            master: masterSecret,
            usage: "Happy Coder",
            path: ["analytics", "id"]
        )
        let anonID = String(HexUtils.encode(anonIDKey).prefix(16)).lowercased()
        XCTAssertEqual(anonID.count, 16)
    }
}

private struct TestSessionMessage: Codable, Equatable {
    let role: String
    let text: String
}
```

**Step 2: Run test to verify it passes**

Run all crypto tests: `xcodebuild test ... -only-testing:TalonTests`
Expected: ALL PASS

**Step 3: Commit**

```
git commit -m "test(crypto): add integration test for full encryption key hierarchy"
```

---

### Task 8: Push and verify CI

**Step 1: Push branch**

```
git push -u origin claude/happy-ios-client-tZAaq
```

**Step 2: Verify CI passes**

Check GitHub Actions — build and test jobs should both pass on `macos-15` with Xcode 16.2.

**Step 3: If CI fails, fix and push again**

Common issues:
- swift-sodium SPM resolution may need `xcodebuild -resolvePackageDependencies` first
- Import paths may differ (module name is `Sodium`, not `swift-sodium`)
- iOS Simulator name/OS version may need adjustment for the runner
