import Foundation
import Security

protocol CredentialStore {
    func readSession() throws -> SpotifySession?
    func save(_ session: SpotifySession) throws
    func deleteSession() throws
}

enum CredentialStoreError: LocalizedError {
    case keychain(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            "Could not access Spotify credentials: \(SecCopyErrorMessageString(status, nil) as String? ?? String(status))."
        case .invalidData: "Saved Spotify credentials could not be read."
        }
    }
}

final class KeychainCredentialStore: CredentialStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.tracklet.spotify",
         kSecAttrAccount as String: "session"]
    }

    func readSession() throws -> SpotifySession? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
        guard let data = result as? Data else { throw CredentialStoreError.invalidData }
        return try JSONDecoder().decode(SpotifySession.self, from: data)
    }

    func save(_ session: SpotifySession) throws {
        let data = try JSONEncoder().encode(session)
        let attributes = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
            // Another process may create the item between our update and add.
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            }
        }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
    }

    func deleteSession() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }
}
