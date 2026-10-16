import Foundation
import Security

/// The account's id and password live only in the Keychain.
enum Keychain {
    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Keychain error \(status)" }
    }

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "edu.columbia.gamebuilder.catherine",
         kSecAttrAccount as String: "account"]
    }

    static func save(_ account: Account) throws {
        delete()
        var item = query()
        item[kSecValueData as String] = try JSONEncoder().encode(account)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func load() -> Account? {
        var item = query()
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }

    static func delete() {
        SecItemDelete(query() as CFDictionary)
    }
}
