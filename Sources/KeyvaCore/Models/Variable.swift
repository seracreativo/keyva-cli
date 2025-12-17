//
//  Variable.swift
//  KeyvaCore
//

import Foundation
import SwiftData

@Model
public final class Variable {
    public var id: UUID = UUID()
    public var key: String = ""
    public var value: String = ""
    public var isSecret: Bool = false
    public var notes: String?
    public var order: Int = 0
    public var timestamp: Date = Date()

    /// Environment IDs this variable applies to
    /// Stored as comma-separated UUIDs: "uuid1,uuid2,uuid3"
    /// At least one environment required
    public var environmentIDs: String = ""

    public var project: Project?

    public init(
        key: String,
        value: String,
        isSecret: Bool = false,
        notes: String? = nil,
        order: Int = 0,
        environmentIDs: Set<UUID>
    ) {
        self.id = UUID()
        self.key = key
        self.value = isSecret ? "[SECURED]" : value
        self.isSecret = isSecret
        self.notes = notes
        self.order = order
        self.environmentIDs = environmentIDs.map { $0.uuidString }.sorted().joined(separator: ",")
        self.timestamp = Date()
    }

    // MARK: - Computed Properties

    /// Get the environment UUIDs this variable applies to
    public var environments: Set<UUID> {
        guard !environmentIDs.isEmpty else { return [] }
        return Set(environmentIDs
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) })
    }

    /// Set the environment UUIDs this variable applies to
    public func setEnvironments(_ ids: Set<UUID>) {
        guard !ids.isEmpty else {
            fatalError("Variable must apply to at least one environment")
        }
        environmentIDs = ids.map { $0.uuidString }.sorted().joined(separator: ",")
    }

    /// Check if this variable applies to a specific environment
    public func appliesTo(_ environmentID: UUID) -> Bool {
        environments.contains(environmentID)
    }

    /// Check if this is a shared variable (applies to multiple environments)
    public var isShared: Bool {
        environments.count > 1
    }
}
