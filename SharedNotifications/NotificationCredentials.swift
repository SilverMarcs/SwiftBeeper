import Foundation
import Security

/// Only the app and its signed notification extension can read this item.
nonisolated enum NotificationCredentials {
    private static var query: [String: Any] {
        get throws {
            guard let group = Bundle.main.object(forInfoDictionaryKey: "RelayNotificationKeychainGroup") as? String,
                  !group.isEmpty else { throw CocoaError(.coderValueNotFound) }
            return [kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: "Relay.notification-preview",
                    kSecAttrAccount as String: "matrix",
                    kSecUseDataProtectionKeychain as String: true,
                    kSecAttrAccessGroup as String: group]
        }
    }

    static func save(_ data: Data) throws {
        if (try? load()) == data { return }
        let query = try query
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            let result = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard result == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        } else if result != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
    }

    static func load() throws -> Data {
        var query = try query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &item)
        guard result == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
        return data
    }

    static func remove() throws {
        let result = SecItemDelete(try query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
    }
}
