//
//  Project.swift
//  KeyvaCore
//

import Foundation
import SwiftData

@Model
public final class Project {
    public var id: UUID = UUID()
    public var name: String = "New Project"

    /// @deprecated Monochrome design - color differentiation no longer used
    /// Kept for backward compatibility. Always returns gray (#8E8E93) in monochrome design.
    public var colorHex: String = "#8E8E93"

    public var icon: String = "folder.fill"
    public var timestamp: Date = Date()

    @Relationship(deleteRule: .cascade)
    public var groups: [EnvironmentGroup]?

    @Relationship(deleteRule: .cascade)
    public var variables: [Variable]?

    public init(name: String, colorHex: String = "#8E8E93", icon: String = "folder.fill") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.timestamp = Date()
    }

    // MARK: - Helper Methods

    /// Get all variables that apply to a specific environment
    public func variables(for environmentID: UUID) -> [Variable] {
        (variables ?? []).filter { $0.appliesTo(environmentID) }
    }
}
