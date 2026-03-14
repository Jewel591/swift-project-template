import Foundation

enum ServerConfig {

    private static let defaultURL = "https://api.cluster-fluster.com"
    private static let storageKey = "happy_custom_server_url"

    static var serverURL: String {
        if let custom = UserDefaults.standard.string(forKey: storageKey) {
            return custom
        }
        return defaultURL
    }

    static var isUsingCustomServer: Bool {
        serverURL != defaultURL
    }

    static func setCustomURL(_ url: String?) {
        if let url = url?.trimmingCharacters(in: .whitespaces), !url.isEmpty {
            UserDefaults.standard.set(url, forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    struct ValidationResult {
        let isValid: Bool
        let error: String?
    }

    static func validate(_ urlString: String) -> ValidationResult {
        guard !urlString.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ValidationResult(isValid: false, error: "Server URL cannot be empty")
        }
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return ValidationResult(isValid: false, error: "Invalid URL format")
        }
        return ValidationResult(isValid: true, error: nil)
    }
}
