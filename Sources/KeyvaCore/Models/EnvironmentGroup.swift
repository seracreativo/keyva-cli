//
//  EnvironmentGroup.swift
//  KeyvaCore
//

import Foundation
import SwiftData

@Model
public final class EnvironmentGroup {
    public var id: UUID = UUID()
    public var name: String = "Development"
    public var icon: String = "folder.fill"
    public var order: Int = 0
    public var timestamp: Date = Date()

    public var project: Project?

    public init(name: String, icon: String = "folder.fill", order: Int = 0) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.order = order
        self.timestamp = Date()
    }

    // MARK: - Icon Suggestions

    /// Suggest appropriate icons based on environment name
    public static func suggestIcons(for name: String) -> [String] {
        let lowercased = name.lowercased()

        if lowercased.contains("dev") {
            return ["hammer.fill", "wrench.fill", "terminal.fill"]
        } else if lowercased.contains("prod") {
            return ["shippingbox.fill", "checkmark.seal.fill", "server.rack"]
        } else if lowercased.contains("test") || lowercased.contains("qa") {
            return ["testtube.2", "checkmark.circle.fill", "sparkles"]
        } else if lowercased.contains("stage") || lowercased.contains("preview") {
            return ["eye.fill", "binoculars.fill", "play.fill"]
        } else {
            return ["folder.fill", "doc.fill", "tray.fill"]
        }
    }
}
