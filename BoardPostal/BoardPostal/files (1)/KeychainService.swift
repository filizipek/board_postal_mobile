import Foundation
import Security

// MARK: - KeychainService
// Stores JWT access + refresh tokens securely in the iOS Keychain.
// Never store tokens in UserDefaults — Keychain only.

final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    private let service = "com.boardpostal.app"

    enum Key: String {
        case accessToken  = "bp_access_token"
        case refreshToken = "bp_refresh_token"
        case userId       = "bp_user_id"
        case username     = "bp_username"
        case email        = "bp_email"
    }

    // MARK: - Save
    @discardableResult
    func save(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        // Try update first
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist — add it
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }

        return updateStatus == errSecSuccess
    }

    // MARK: - Load
    func load(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key.rawValue,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }

        return value
    }

    // MARK: - Delete
    @discardableResult
    func delete(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Clear all (on logout)
    func clearAll() {
        Key.allCases.forEach { delete($0) }
    }
}

extension KeychainService.Key: CaseIterable {}

// MARK: - Token convenience accessors
extension KeychainService {
    var accessToken: String? {
        get { load(.accessToken) }
        set {
            if let value = newValue { save(value, for: .accessToken) }
            else { delete(.accessToken) }
        }
    }

    var refreshToken: String? {
        get { load(.refreshToken) }
        set {
            if let value = newValue { save(value, for: .refreshToken) }
            else { delete(.refreshToken) }
        }
    }

    var userId: String? {
        get { load(.userId) }
        set {
            if let v = newValue { save(v, for: .userId) }
            else { delete(.userId) }
        }
    }

    var email: String? {
        get { load(.email) }
        set {
            if let v = newValue { save(v, for: .email) }
            else { delete(.email) }
        }
    }

    var isLoggedIn: Bool {
        accessToken != nil && refreshToken != nil
    }

    func saveTokens(access: String, refresh: String, userId: String, email: String) {
        accessToken = access
        refreshToken = refresh
        self.userId = userId
        self.email = email
    }
}
