import Foundation
import Sodium

/// Represents the QR code payload sent to the desktop.
struct QRPayload {
    let publicKey: Data     // 32 bytes X25519
    let secretKey: Data     // 32 bytes X25519
    let qrString: String    // base64 of publicKey for QR display
}

/// Response from the desktop after scanning QR.
struct AuthResponse: Decodable {
    let token: String
    let encryptedSecret: String  // base64 of Box-encrypted master secret
}

/// Polling status for auth request.
enum AuthRequestStatus: Decodable {
    case pending
    case approved(token: String, encryptedSecret: String)
    case rejected

    enum CodingKeys: String, CodingKey {
        case status
        case token
        case encryptedSecret
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)

        switch status {
        case "pending":
            self = .pending
        case "approved":
            let token = try container.decode(String.self, forKey: .token)
            let encryptedSecret = try container.decode(String.self, forKey: .encryptedSecret)
            self = .approved(token: token, encryptedSecret: encryptedSecret)
        case "rejected":
            self = .rejected
        default:
            self = .pending
        }
    }
}

enum QRAuthError: Error {
    case keypairGenerationFailed
    case decryptionFailed
    case invalidSecret
    case pollingCancelled
    case authRejected
    case invalidBase64
}

enum QRAuthFlow {

    private static let sodium = Sodium()

    // MARK: - Step 1: Generate Box keypair for QR

    /// Generate an ephemeral X25519 keypair for the QR code flow.
    /// The public key is displayed as a QR code for the desktop to scan.
    static func generateQRPayload() throws -> QRPayload {
        guard let kp = sodium.box.keyPair() else {
            throw QRAuthError.keypairGenerationFailed
        }

        let publicKeyData = Data(kp.publicKey)
        let secretKeyData = Data(kp.secretKey)
        let qrString = Base64Utils.encode(publicKeyData)

        return QRPayload(
            publicKey: publicKeyData,
            secretKey: secretKeyData,
            qrString: qrString
        )
    }

    // MARK: - Step 2: Decrypt master secret from desktop response

    /// Decrypt the master secret that was Box-encrypted by the desktop.
    /// The desktop encrypts the 32-byte master secret to our ephemeral public key.
    static func decryptMasterSecret(
        encryptedBase64: String,
        recipientSecretKey: Data
    ) throws -> Data {
        guard let encryptedData = Base64Utils.decode(encryptedBase64) else {
            throw QRAuthError.invalidBase64
        }

        do {
            let secret = try BoxCrypto.decrypt(encryptedData, recipientSecretKey: recipientSecretKey)
            guard secret.count == 32 else {
                throw QRAuthError.invalidSecret
            }
            return secret
        } catch {
            throw QRAuthError.decryptionFailed
        }
    }

    // MARK: - Step 3: Authenticate with challenge-response

    /// After obtaining the master secret, perform challenge-response auth.
    /// Returns the bearer token for API access.
    static func authenticate(masterSecret: Data) async throws -> String {
        let result = AuthChallenge.create(secret: masterSecret)

        let request = HappyAPIClient.buildAuthRequest(
            challenge: result.challenge,
            signature: result.signature,
            publicKey: result.publicKey
        )

        let response: AuthResponse = try await HappyAPIClient.execute(request)
        return response.token
    }

    // MARK: - Step 4: Store credentials

    /// Store the authenticated credentials in Keychain.
    static func storeCredentials(token: String, masterSecret: Data) async throws {
        let credentials = AuthCredentials(
            token: token,
            masterSecretBase64URL: Base64Utils.encodeURL(masterSecret)
        )
        try await CredentialStore.store(credentials)
    }

    // MARK: - Full flow (encrypt/decrypt round-trip helper for testing)

    /// Encrypt a master secret for a recipient (simulates desktop side).
    /// Used for testing the QR flow end-to-end.
    static func encryptForRecipient(
        masterSecret: Data,
        recipientPublicKey: Data
    ) throws -> String {
        let encrypted = try BoxCrypto.encrypt(masterSecret, recipientPublicKey: recipientPublicKey)
        return Base64Utils.encode(encrypted)
    }
}
