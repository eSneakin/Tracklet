import Foundation
import Security

protocol CredentialStore {
    func readSession() throws -> SpotifySession?
    func save(_ session: SpotifySession) throws
    func deleteSession() throws
}

enum CredentialStoreError: Error {
    case keychain(OSStatus)
    case invalidData
}

final class KeychainCredentialStore: CredentialStore {
    private let service = "com.tracklet.spotify"
    private let account = "session"

    func readSession() throws -> SpotifySession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw CredentialStoreError.keychain(status) }
        guard let data = result as? Data else { throw CredentialStoreError.invalidData }
        return try JSONDecoder().decode(SpotifySession.self, from: data)
    }

    func save(_ session: SpotifySession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychain(addStatus)
            }
        } else if status != errSecSuccess {
            throw CredentialStoreError.keychain(status)
        }
    }

    func deleteSession() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }
}
