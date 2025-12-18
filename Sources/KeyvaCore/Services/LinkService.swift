//
//  LinkService.swift
//  KeyvaCore
//
//  Manages directory-to-project links for simplified CLI workflow
//

import Foundation

/// Service to link directories to Keyva projects
/// Allows commands like `keyva export prod` instead of `keyva export --project "Ulula" --env "Production"`
public class LinkService {
    public static let shared = LinkService()

    private let configFileName = ".keyva"
    private let globalConfigFileName = "links.json"

    private init() {}

    // MARK: - Link Configuration

    public struct LinkConfig: Codable {
        public var projectName: String
        public var defaultEnvironment: String?

        public init(projectName: String, defaultEnvironment: String? = nil) {
            self.projectName = projectName
            self.defaultEnvironment = defaultEnvironment
        }
    }

    // MARK: - Local Link (per directory)

    /// Link current directory to a project
    public func link(directory: URL, to projectName: String, defaultEnv: String? = nil) throws {
        let configURL = directory.appendingPathComponent(configFileName)
        let config = LinkConfig(projectName: projectName, defaultEnvironment: defaultEnv)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(config)
        try data.write(to: configURL)
    }

    /// Unlink current directory
    public func unlink(directory: URL) throws {
        let configURL = directory.appendingPathComponent(configFileName)
        if FileManager.default.fileExists(atPath: configURL.path) {
            try FileManager.default.removeItem(at: configURL)
        }
    }

    /// Get link configuration for a directory (searches up the tree)
    public func getLink(for directory: URL) -> LinkConfig? {
        var currentDir = directory

        // Search up the directory tree
        while true {
            let configURL = currentDir.appendingPathComponent(configFileName)

            if FileManager.default.fileExists(atPath: configURL.path) {
                do {
                    let data = try Data(contentsOf: configURL)
                    let config = try JSONDecoder().decode(LinkConfig.self, from: data)
                    return config
                } catch {
                    return nil
                }
            }

            // Move to parent directory
            let parent = currentDir.deletingLastPathComponent()
            if parent == currentDir {
                // Reached root
                break
            }
            currentDir = parent
        }

        // Check global links
        return getGlobalLink(for: directory)
    }

    // MARK: - Global Links

    private var globalLinksURL: URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            #if os(macOS)
            // Fallback to home directory for CLI (macOS only)
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            return homeDir.appendingPathComponent(".keyva").appendingPathComponent(globalConfigFileName)
            #else
            return nil
            #endif
        }
        return containerURL.appendingPathComponent(globalConfigFileName)
    }

    /// Add a global link (stored in App Group container)
    public func addGlobalLink(directory: URL, to projectName: String, defaultEnv: String? = nil) throws {
        var links = loadGlobalLinks()
        links[directory.path] = LinkConfig(projectName: projectName, defaultEnvironment: defaultEnv)
        try saveGlobalLinks(links)
    }

    /// Remove a global link
    public func removeGlobalLink(for directory: URL) throws {
        var links = loadGlobalLinks()
        links.removeValue(forKey: directory.path)
        try saveGlobalLinks(links)
    }

    /// Get global link for directory
    public func getGlobalLink(for directory: URL) -> LinkConfig? {
        let links = loadGlobalLinks()

        // Check exact match first
        if let config = links[directory.path] {
            return config
        }

        // Check if directory is subdirectory of a linked directory
        for (linkedPath, config) in links {
            if directory.path.hasPrefix(linkedPath + "/") {
                return config
            }
        }

        return nil
    }

    /// List all global links
    public func listGlobalLinks() -> [String: LinkConfig] {
        return loadGlobalLinks()
    }

    private func loadGlobalLinks() -> [String: LinkConfig] {
        guard let url = globalLinksURL else { return [:] }

        // Ensure directory exists
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: LinkConfig].self, from: data)
        } catch {
            return [:]
        }
    }

    private func saveGlobalLinks(_ links: [String: LinkConfig]) throws {
        guard let url = globalLinksURL else {
            throw LinkError.noStorageAccess
        }

        // Ensure directory exists
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(links)
        try data.write(to: url)
    }

    // MARK: - Environment Shortcuts

    /// Common environment name shortcuts
    public static let environmentAliases: [String: [String]] = [
        "prod": ["Production", "production", "Prod", "PROD", "prod", "live", "Live"],
        "dev": ["Development", "development", "Dev", "DEV", "dev", "local", "Local"],
        "staging": ["Staging", "staging", "Stage", "STAGE", "stage", "test", "Test"],
        "qa": ["QA", "qa", "Quality", "quality"]
    ]

    /// Resolve environment alias to actual name
    public func resolveEnvironmentName(_ alias: String, in project: Project) -> String? {
        // First, check exact match
        if let _ = project.groups?.first(where: { $0.name.lowercased() == alias.lowercased() }) {
            return alias
        }

        // Check aliases
        if let possibleNames = Self.environmentAliases[alias.lowercased()] {
            for name in possibleNames {
                if let env = project.groups?.first(where: { $0.name.lowercased() == name.lowercased() }) {
                    return env.name
                }
            }
        }

        return nil
    }
}

// MARK: - Errors

public enum LinkError: Error, LocalizedError {
    case noStorageAccess
    case notLinked
    case projectNotFound(String)
    case environmentNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .noStorageAccess:
            return "Cannot access storage for links"
        case .notLinked:
            return "Current directory is not linked to a project. Use 'keyva link <project>' first."
        case .projectNotFound(let name):
            return "Project '\(name)' not found"
        case .environmentNotFound(let name):
            return "Environment '\(name)' not found"
        }
    }
}
