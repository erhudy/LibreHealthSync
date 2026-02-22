import Foundation
import Security

nonisolated struct KeychainService: Sendable {
    private let service = "com.librehealthsync"

    private enum Key: String {
        case email
        case password
        case token
        case userId
        case region
    }

    // MARK: - Email

    func saveEmail(_ email: String) {
        save(key: .email, value: email)
    }

    func getEmail() -> String? {
        get(key: .email)
    }

    // MARK: - Password

    func savePassword(_ password: String) {
        save(key: .password, value: password)
    }

    func getPassword() -> String? {
        get(key: .password)
    }

    // MARK: - Token

    func saveToken(_ token: String) {
        save(key: .token, value: token)
    }

    func getToken() -> String? {
        get(key: .token)
    }

    // MARK: - User ID

    func saveUserId(_ userId: String) {
        save(key: .userId, value: userId)
    }

    func getUserId() -> String? {
        get(key: .userId)
    }

    // MARK: - Region

    func saveRegion(_ region: LibreLinkUpRegion) {
        save(key: .region, value: region.rawValue)
    }

    func getRegion() -> LibreLinkUpRegion? {
        guard let raw = get(key: .region) else { return nil }
        return LibreLinkUpRegion(rawValue: raw)
    }

    // MARK: - Delete All

    func deleteAll() {
        for key in [Key.email, .password, .token, .userId, .region] {
            delete(key: key)
        }
    }

    // MARK: - Private Helpers

    private func save(key: Key, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private func get(key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return string
    }

    private func delete(key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]

        SecItemDelete(query as CFDictionary)
    }
}
