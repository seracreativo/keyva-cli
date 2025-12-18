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
///
/// Key storage: The encryption key is stored in the App Group container (not Keychain)
/// so that both the app and CLI can access it.
public actor SecureStorage {
    public static let shared = SecureStorage()

    private let secretsFileName = "secrets.encrypted"
    private let keyFileName = "encryption.key"

    private var cachedSecrets: [String: String]? = nil

    private init() {}

    // MARK: - File URLs

    private var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    private var storageURL: URL? {
        containerURL?.appendingPathComponent(secretsFileName)
    }

    private var keyURL: URL? {
        containerURL?.appendingPathComponent(keyFileName)
    }

    // MARK: - Encryption Key Management

    /// Get or create the encryption key from App Group container
    /// This key is stored as a file and used to encrypt/decrypt the secrets file
    private func getOrCreateKey() throws -> SymmetricKey {
        guard let keyURL = keyURL else {
            throw SecureStorageError.noAppGroupAccess
        }

        // Try to read existing key from file
        if FileManager.default.fileExists(atPath: keyURL.path) {
            let keyData = try Data(contentsOf: keyURL)
            if keyData.count == 32 { // 256 bits
                return SymmetricKey(data: keyData)
            }
        }

        // Create new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        // Write to App Group container
        try keyData.write(to: keyURL, options: [.atomic, .completeFileProtection])

        return newKey
    }

    /// Check if encryption key exists
    public func hasEncryptionKey() -> Bool {
        guard let keyURL = keyURL else { return false }
        return FileManager.default.fileExists(atPath: keyURL.path)
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
        do {
            let secrets = try loadAllSecrets()
            guard let value = secrets[variableId.uuidString] else {
                throw SecureStorageError.secretNotFound
            }
            return value
        } catch {
            print("🔐 SecureStorage retrieve error for \(variableId): \(error)")
            throw error
        }
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

    /// Reset storage - delete secrets file and key (for migration from old key storage)
    /// Call this when migrating from Keychain-based key to file-based key
    public func resetStorage() throws {
        cachedSecrets = nil

        // Delete secrets file
        if let url = storageURL, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            print("🔐 Deleted old secrets file")
        }

        // Delete key file (new key will be created on next save)
        if let url = keyURL, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            print("🔐 Deleted old encryption key")
        }
    }

    /// Check if storage needs reset (key exists in Keychain but not in file)
    /// This detects the old storage format
    public func needsReset() -> Bool {
        let hasFileKey = hasEncryptionKey()

        // If we have secrets file but no file-based key, need reset
        if let url = storageURL,
           FileManager.default.fileExists(atPath: url.path),
           !hasFileKey {
            print("🔐 Detected old storage format (Keychain key), needs reset")
            return true
        }

        return false
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
