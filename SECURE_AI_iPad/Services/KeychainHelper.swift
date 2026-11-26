import Foundation
import Security

/// Persists sensitive values (License Key, Stable Device ID, Saved SECURE Logins) in Apple Keychain
/// so they SURVIVE app reinstalls and updates on iPad Pro.
enum KeychainHelper {
    private static let service = "com.secureai.ipad.pro.keychain"

    static func save(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        saveData(data, forKey: key)
    }

    static func loadString(forKey key: String) -> String? {
        guard let data = loadData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveData(_ data: Data, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(newItem as CFDictionary, nil)
    }

    static func loadData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct SavedSecureLogin: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String
    var userId: String
    var password: String
}

@MainActor
final class SavedLoginStore: ObservableObject {
    private static let keychainKey = "saved_secure_logins_v1"
    @Published var accounts: [SavedSecureLogin] = []

    init() {
        load()
    }

    func load() {
        if let data = KeychainHelper.loadData(forKey: Self.keychainKey),
           let decoded = try? JSONDecoder().decode([SavedSecureLogin].self, from: data) {
            accounts = decoded
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            KeychainHelper.saveData(data, forKey: Self.keychainKey)
        }
    }

    func add(label: String, userId: String, password: String) {
        let cleanUser = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty else { return }
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = SavedSecureLogin(
            label: cleanLabel.isEmpty ? cleanUser : cleanLabel,
            userId: cleanUser,
            password: password
        )
        accounts.removeAll { $0.userId.caseInsensitiveCompare(cleanUser) == .orderedSame }
        accounts.insert(entry, at: 0)
        save()
    }

    func delete(_ account: SavedSecureLogin) {
        accounts.removeAll { $0.id == account.id }
        save()
    }
}
