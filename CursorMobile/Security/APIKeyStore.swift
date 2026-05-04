import Foundation
import Security

protocol APIKeyStore {
    func loadAPIKey() throws -> String?
    func saveAPIKey(_ apiKey: String) throws
    func deleteAPIKey() throws
}

enum APIKeyStoreAccount: String {
    case cursorCloudAgent = "cursor-cloud-agent"
    case cursorEnterpriseAdmin = "cursor-enterprise-admin"
}

enum APIKeyStoreError: LocalizedError {
    case unhandledStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            "Keychain returned status \(status)."
        case .invalidData:
            "The saved API key could not be read."
        }
    }
}

struct KeychainAPIKeyStore: APIKeyStore {
    private let service: String
    private let account: String

    init(
        service: String = "com.matthewparris.runline.cursor-api-key",
        account: APIKeyStoreAccount = .cursorCloudAgent
    ) {
        self.service = service
        self.account = account.rawValue
    }

    func loadAPIKey() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw APIKeyStoreError.unhandledStatus(status)
        }
        guard
            let data = item as? Data,
            let apiKey = String(data: data, encoding: .utf8)
        else {
            throw APIKeyStoreError.invalidData
        }
        return apiKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        try deleteAPIKey()

        var query = baseQuery
        query[kSecValueData as String] = Data(apiKey.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw APIKeyStoreError.unhandledStatus(status)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.unhandledStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

final class InMemoryAPIKeyStore: APIKeyStore {
    private var apiKey: String?

    init(apiKey: String? = nil) {
        self.apiKey = apiKey
    }

    func loadAPIKey() throws -> String? {
        apiKey
    }

    func saveAPIKey(_ apiKey: String) throws {
        self.apiKey = apiKey
    }

    func deleteAPIKey() throws {
        apiKey = nil
    }
}
