//
//  KeychainService.swift
//  KeyvaCore
//
//  Dual storage: Keychain (primary, app-only) + SecureStorage (shared with CLI)
//

import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "Item already exists in Keychain"
        case .itemNotFound:
            return "Item not found in Keychain"
        case .unexpectedStatus(let status):
            return "Keychain error: \(status)"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

public actor KeychainService {
    public static let shared = KeychainService()

    private let serviceName = "com.seracreativo.keyva.secrets"
    private let secureStorage = SecureStorage.shared

    private init() {}

    /// Save a secret value to both Keychain and SecureStorage
    /// - Parameters:
    ///   - value: The secret value to store
    ///   - variableId: The UUID of the Variable
    public func save(value: String, for variableId: UUID) async throws {
        // Save to Keychain (primary - for app)
        try saveToKeychain(value: value, for: variableId)

        // Also save to SecureStorage (for CLI access)
        try await secureStorage.save(value: value, for: variableId)
    }

    /// Retrieve a secret value - tries Keychain first, then SecureStorage
    /// - Parameter variableId: The UUID of the Variable
    /// - Returns: The secret value
    public func retrieve(for variableId: UUID) async throws -> String {
        // Try Keychain first (app has access)
        if let value = try? retrieveFromKeychain(for: variableId) {
            return value
        }

        // Fall back to SecureStorage (CLI uses this)
        return try await secureStorage.retrieve(for: variableId)
    }

    /// Delete a secret from both Keychain and SecureStorage
    /// - Parameter variableId: The UUID of the Variable
    public func delete(for variableId: UUID) async throws {
        // Delete from Keychain
        try? deleteFromKeychain(for: variableId)

        // Delete from SecureStorage
        try? await secureStorage.delete(for: variableId)
    }

    /// Check if a secret exists in either storage
    /// - Parameter variableId: The UUID of the Variable
    /// - Returns: True if the secret exists
    public func exists(for variableId: UUID) async -> Bool {
        if existsInKeychain(for: variableId) {
            return true
        }
        return await secureStorage.exists(for: variableId)
    }

    // MARK: - Migration

    /// Migrate all secrets from Keychain to SecureStorage
    /// Call this from the app on launch to ensure CLI can access secrets
    public func migrateToSecureStorage(variableIds: [UUID]) async throws {
        var secretsToMigrate: [UUID: String] = [:]

        for id in variableIds {
            if let value = try? retrieveFromKeychain(for: id) {
                // Check if already in SecureStorage
                let existsInSecure = await secureStorage.exists(for: id)
                if !existsInSecure {
                    secretsToMigrate[id] = value
                }
            }
        }

        if !secretsToMigrate.isEmpty {
            try await secureStorage.saveAll(secretsToMigrate)
            print("✅ Migrated \(secretsToMigrate.count) secrets to SecureStorage for CLI access")
        }
    }

    // MARK: - Keychain Operations (Private)

    private func saveToKeychain(value: String, for variableId: UUID) throws {
        let account = variableId.uuidString

        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        // First, try to delete any existing item
        try? deleteFromKeychain(for: variableId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            // Update existing item
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func retrieveFromKeychain(for variableId: UUID) throws -> String {
        let account = variableId.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return string
    }

    private func deleteFromKeychain(for variableId: UUID) throws {
        let account = variableId.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func existsInKeychain(for variableId: UUID) -> Bool {
        let account = variableId.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
