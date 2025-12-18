//
//  SecureStorage.swift
//  KeyvaCore
//
//  Encrypted secrets storage in App Group container (accessible by CLI)
//

import Foundation
import CryptoKit

/// Encrypted storage for secrets in App Group container
/// This allows the CLI to read secrets that were saved by the app
public actor SecureStorage {
    public static let shared = SecureStorage()

    private let fileName = "secrets.encrypted"
    private let keyName = "com.seracreativo.keyva.encryption.key"

    private var cachedSecrets: [String: String]? = nil

    private init() {}

    // MARK: - File URL

    private var storageURL: URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent(fileName)
    }

    // MARK: - Encryption Key Management

    /// Get or create the encryption key from Keychain
    /// This key is stored in Keychain and used to encrypt/decrypt the secrets file
    private func getOrCreateKey() throws -> SymmetricKey {
        // Try to retrieve existing key
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyName,
            kSecAttrAccount as String: "encryption-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let keyData = result as? Data {
            return SymmetricKey(data: keyData)
        }

        // Create new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyName,
            kSecAttrAccount as String: "encryption-key",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecureStorageError.keyCreationFailed
        }

        return newKey
    }

    /// Check if encryption key exists (for CLI to know if it can read secrets)
    public func hasEncryptionKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyName,
            kSecAttrAccount as String: "encryption-key",
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Save/Load Secrets

    /// Save a secret to the encrypted storage
    public func save(value: String, for variableId: UUID) throws {
        var secrets = try loadAllSecrets()
        secrets[variableId.uuidString] = value
        try saveAllSecrets(secrets)
        cachedSecrets = secrets
    }

    /// Retrieve a secret from the encrypted storage
    public func retrieve(for variableId: UUID) throws -> String {
        let secrets = try loadAllSecrets()
        guard let value = secrets[variableId.uuidString] else {
            throw SecureStorageError.secretNotFound
        }
        return value
    }

    /// Delete a secret from the encrypted storage
    public func delete(for variableId: UUID) throws {
        var secrets = try loadAllSecrets()
        secrets.removeValue(forKey: variableId.uuidString)
        try saveAllSecrets(secrets)
        cachedSecrets = secrets
    }

    /// Check if a secret exists
    public func exists(for variableId: UUID) -> Bool {
        guard let secrets = try? loadAllSecrets() else { return false }
        return secrets[variableId.uuidString] != nil
    }

    // MARK: - Bulk Operations

    /// Save multiple secrets at once (more efficient for migration)
    public func saveAll(_ secrets: [UUID: String]) throws {
        var existing = (try? loadAllSecrets()) ?? [:]
        for (id, value) in secrets {
            existing[id.uuidString] = value
        }
        try saveAllSecrets(existing)
        cachedSecrets = existing
    }

    /// Get all secret IDs
    public func allSecretIds() throws -> [UUID] {
        let secrets = try loadAllSecrets()
        return secrets.keys.compactMap { UUID(uuidString: $0) }
    }

    // MARK: - Private Helpers

    private func loadAllSecrets() throws -> [String: String] {
        // Return cached if available
        if let cached = cachedSecrets {
            return cached
        }

        guard let url = storageURL else {
            return [:]
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }

        let encryptedData = try Data(contentsOf: url)

        // If file is empty, return empty dict
        guard !encryptedData.isEmpty else {
            return [:]
        }

        let key = try getOrCreateKey()

        // Decrypt
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        let secrets = try JSONDecoder().decode([String: String].self, from: decryptedData)
        cachedSecrets = secrets
        return secrets
    }

    private func saveAllSecrets(_ secrets: [String: String]) throws {
        guard let url = storageURL else {
            throw SecureStorageError.noAppGroupAccess
        }

        let key = try getOrCreateKey()

        // Encode to JSON
        let jsonData = try JSONEncoder().encode(secrets)

        // Encrypt
        let sealedBox = try AES.GCM.seal(jsonData, using: key)
        guard let encryptedData = sealedBox.combined else {
            throw SecureStorageError.encryptionFailed
        }

        // Write to file
        try encryptedData.write(to: url, options: .atomic)
    }

    /// Clear cache (useful after sync operations)
    public func clearCache() {
        cachedSecrets = nil
    }
}

// MARK: - Errors

public enum SecureStorageError: Error, LocalizedError {
    case noAppGroupAccess
    case keyCreationFailed
    case encryptionFailed
    case decryptionFailed
    case secretNotFound

    public var errorDescription: String? {
        switch self {
        case .noAppGroupAccess:
            return "Cannot access App Group container"
        case .keyCreationFailed:
            return "Failed to create encryption key"
        case .encryptionFailed:
            return "Failed to encrypt secrets"
        case .decryptionFailed:
            return "Failed to decrypt secrets"
        case .secretNotFound:
            return "Secret not found"
        }
    }
}
