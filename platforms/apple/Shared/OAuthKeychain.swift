import Foundation
import Security

/// Keychain storage for Velox user OAuth tokens (not per-slug edit tokens).
enum OAuthKeychain {
    private static let service = AgentCanvasConstants.oauthKeychainService

    enum Account: String {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case clientId = "client_id"
        case resource = "resource"
        case idToken = "id_token"
    }

    static func get(_ account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, account: Account) -> Bool {
        delete(account)
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(_ account: Account) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func clearAll() {
        for account in [Account.accessToken, .refreshToken, .expiresAt, .clientId, .resource, .idToken] {
            delete(account)
        }
    }

    static var hasRefreshToken: Bool {
        guard let t = get(.refreshToken), !t.isEmpty else { return false }
        return true
    }

    static var hasAccessToken: Bool {
        guard let t = get(.accessToken), !t.isEmpty else { return false }
        return true
    }

    static var expiresAt: Date? {
        guard let raw = get(.expiresAt) else { return nil }
        if let epoch = TimeInterval(raw) {
            return Date(timeIntervalSince1970: epoch)
        }
        return ISO8601DateFormatter().date(from: raw)
    }

    static func saveTokens(
        accessToken: String,
        refreshToken: String?,
        expiresIn: TimeInterval?,
        clientId: String?,
        resource: String?,
        idToken: String?
    ) {
        set(accessToken, account: .accessToken)
        if let refreshToken, !refreshToken.isEmpty {
            set(refreshToken, account: .refreshToken)
        }
        let expires = Date().addingTimeInterval(expiresIn ?? 600)
        set(String(expires.timeIntervalSince1970), account: .expiresAt)
        if let clientId, !clientId.isEmpty {
            set(clientId, account: .clientId)
        }
        if let resource, !resource.isEmpty {
            set(resource, account: .resource)
        }
        if let idToken, !idToken.isEmpty {
            set(idToken, account: .idToken)
        }
    }
}
