//
//  main.swift
//  keyva CLI
//
//  Command-line interface for Keyva environment management
//

import ArgumentParser
import KeyvaCore
import Foundation

@main
struct Keyva: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keyva",
        abstract: "Environment variables manager for developers",
        version: "1.2.0",
        subcommands: [
            ProjectCommand.self,
            EnvCommand.self,
            VarCommand.self,
            ExportCommand.self,
            LinkCommand.self,
            PullCommand.self,
            DiagCommand.self,
        ]
    )
}

// MARK: - Diagnostic Command

struct DiagCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diag",
        abstract: "Diagnostic information for troubleshooting"
    )

    @MainActor
    func run() async throws {
        print("Keyva CLI Diagnostics")
        print("=====================\n")

        // App Group
        let appGroup = "group.com.seracreativo.keyva"
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            print("✅ App Group: \(appGroup)")
            print("   Path: \(containerURL.path)")

            // Check files
            let secretsFile = containerURL.appendingPathComponent("secrets.encrypted")
            let keyFile = containerURL.appendingPathComponent("encryption.key")

            if FileManager.default.fileExists(atPath: secretsFile.path) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: secretsFile.path)
                let size = attrs?[.size] as? Int ?? 0
                print("   📁 secrets.encrypted: \(size) bytes")
            } else {
                print("   📁 secrets.encrypted: NOT FOUND")
            }

            if FileManager.default.fileExists(atPath: keyFile.path) {
                let attrs = try? FileManager.default.attributesOfItem(atPath: keyFile.path)
                let size = attrs?[.size] as? Int ?? 0
                print("   🔑 encryption.key: \(size) bytes")
            } else {
                print("   🔑 encryption.key: NOT FOUND (needs app migration)")
            }
        } else {
            print("❌ App Group: Cannot access \(appGroup)")
        }

        print("")

        // SecureStorage status
        let secureStorage = SecureStorage.shared
        if await secureStorage.hasEncryptionKey() {
            print("✅ SecureStorage: Key available")
            do {
                let ids = try await secureStorage.allSecretIds()
                print("   Secrets stored: \(ids.count)")
            } catch {
                print("   ⚠️ Cannot read secrets: \(error)")
            }
        } else {
            print("⚠️ SecureStorage: No encryption key")
            print("   Run the Keyva app to initialize storage")
        }

        if await secureStorage.needsReset() {
            print("\n⚠️ Storage needs migration to new format")
            print("   Please launch the Keyva macOS app to migrate")
        }

        print("")

        // DataStore
        print("📊 DataStore:")
        let store = DataStore.shared
        do {
            let projects = try store.listProjects()
            print("   Projects: \(projects.count)")

            var totalSecrets = 0
            for project in projects {
                let secrets = (project.variables ?? []).filter { $0.isSecret }
                totalSecrets += secrets.count
            }
            print("   Total secrets: \(totalSecrets)")
        } catch {
            print("   ❌ Error: \(error)")
        }
    }
}

// MARK: - Project Commands

struct ProjectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project",
        abstract: "Manage projects",
        subcommands: [
            ProjectList.self,
            ProjectCreate.self,
            ProjectDelete.self,
        ]
    )
}

struct ProjectList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all projects"
    )

    @MainActor
    func run() async throws {
        let store = DataStore.shared
        let projects = try store.listProjects()

        if projects.isEmpty {
            print("No projects found.")
            print("Create one with: keyva project create \"MyProject\"")
            return
        }

        print("Projects (\(projects.count)):")
        for project in projects {
            let envCount = project.groups?.count ?? 0
            let varCount = project.variables?.count ?? 0
            print("  • \(project.name) (\(envCount) envs, \(varCount) vars)")
        }
    }
}

struct ProjectCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new project"
    )

    @Argument(help: "Project name")
    var name: String

    @Option(name: .shortAndLong, help: "SF Symbol icon name")
    var icon: String = "folder.fill"

    @Flag(name: .long, help: "Create with default environments (Development, Staging, Production)")
    var withDefaults: Bool = false

    @MainActor
    func run() async throws {
        let store = DataStore.shared

        // Check if project already exists
        if let _ = try store.getProject(name: name) {
            print("Error: Project '\(name)' already exists.")
            throw ExitCode.failure
        }

        let project = try store.createProject(name: name, icon: icon)
        print("✓ Created project '\(project.name)'")

        // Create default environments if requested
        if withDefaults {
            let defaults = [
                ("Development", "hammer.fill"),
                ("Staging", "shippingbox.fill"),
                ("Production", "bolt.fill")
            ]

            for (envName, envIcon) in defaults {
                _ = try store.createEnvironment(name: envName, icon: envIcon, in: project)
                print("  ✓ Created environment '\(envName)'")
            }
        }
    }
}

struct ProjectDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a project"
    )

    @Argument(help: "Project name")
    var name: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force: Bool = false

    @MainActor
    func run() async throws {
        let store = DataStore.shared

        guard let project = try store.getProject(name: name) else {
            print("Error: Project '\(name)' not found.")
            throw ExitCode.failure
        }

        if !force {
            print("Delete project '\(name)' and all its data? [y/N] ", terminator: "")
            guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
                print("Cancelled.")
                return
            }
        }

        try await store.deleteProject(project)
        print("✓ Deleted project '\(name)'")
    }
}

// MARK: - Environment Commands

struct EnvCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "env",
        abstract: "Manage environments",
        subcommands: [
            EnvList.self,
            EnvCreate.self,
            EnvDelete.self,
        ]
    )
}

struct EnvList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List environments in a project"
    )

    @Option(name: .shortAndLong, help: "Project name (optional if directory is linked)")
    var project: String?

    @MainActor
    func run() async throws {
        let store = DataStore.shared
        let projectName = try resolveProjectName(project)

        guard let proj = try store.getProject(name: projectName) else {
            print("Error: Project '\(projectName)' not found.")
            throw ExitCode.failure
        }

        let envs = store.listEnvironments(in: proj)

        if envs.isEmpty {
            print("No environments in '\(projectName)'.")
            print("Create one with: keyva env create \"dev\" --project \"\(projectName)\"")
            return
        }

        print("Environments in '\(projectName)' (\(envs.count)):")
        for env in envs {
            let varCount = proj.variables(for: env.id).count
            print("  • \(env.name) (\(varCount) vars)")
        }
    }
}

struct EnvCreate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new environment"
    )

    @Argument(help: "Environment name (or 'defaults' to create Development, Staging, Production)")
    var name: String

    @Option(name: .shortAndLong, help: "Project name (optional if directory is linked)")
    var project: String?

    @Option(name: .shortAndLong, help: "SF Symbol icon name")
    var icon: String = "folder.fill"

    @MainActor
    func run() async throws {
        let store = DataStore.shared
        let projectName = try resolveProjectName(project)

        guard let proj = try store.getProject(name: projectName) else {
            print("Error: Project '\(projectName)' not found.")
            throw ExitCode.failure
        }

        // Special case: create defaults
        if name.lowercased() == "defaults" {
            let defaults = [
                ("Development", "hammer.fill"),
                ("Staging", "shippingbox.fill"),
                ("Production", "bolt.fill")
            ]

            for (envName, envIcon) in defaults {
                if store.getEnvironment(name: envName, in: proj) == nil {
                    _ = try store.createEnvironment(name: envName, icon: envIcon, in: proj)
                    print("✓ Created environment '\(envName)' in '\(projectName)'")
                } else {
                    print("  • '\(envName)' already exists")
                }
            }
            return
        }

        // Check if env already exists
        if let _ = store.getEnvironment(name: name, in: proj) {
            print("Error: Environment '\(name)' already exists in '\(projectName)'.")
            throw ExitCode.failure
        }

        // Suggest icon based on name
        let suggestedIcons = EnvironmentGroup.suggestIcons(for: name)
        let finalIcon = icon == "folder.fill" ? suggestedIcons.first ?? icon : icon

        let env = try store.createEnvironment(name: name, icon: finalIcon, in: proj)
        print("✓ Created environment '\(env.name)' in '\(projectName)'")
    }
}

struct EnvDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete an environment"
    )

    @Argument(help: "Environment name")
    var name: String

    @Option(name: .shortAndLong, help: "Project name (optional if directory is linked)")
    var project: String?

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force: Bool = false

    @MainActor
    func run() async throws {
        let store = DataStore.shared
        let projectName = try resolveProjectName(project)

        guard let proj = try store.getProject(name: projectName) else {
            print("Error: Project '\(projectName)' not found.")
            throw ExitCode.failure
        }

        guard let env = store.getEnvironment(name: name, in: proj) else {
            print("Error: Environment '\(name)' not found in '\(projectName)'.")
            throw ExitCode.failure
        }

        if !force {
            print("Delete environment '\(name)' from '\(projectName)'? [y/N] ", terminator: "")
            guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
                print("Cancelled.")
                return
            }
        }

        try await store.deleteEnvironment(env, in: proj)
        print("✓ Deleted environment '\(name)' from '\(projectName)'")
    }
}

// MARK: - Variable Commands

struct VarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "var",
        abstract: "Manage variables",
        subcommands: [
            VarList.self,
            VarSet.self,
            VarGet.self,
            VarDelete.self,
        ]
    )
}

struct VarList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List variables in an environment"
    )

    @Option(name: .shortAndLong, help: "Project name (optional if directory is linked)")
    var project: String?

    @Option(name: .shortAndLong, help: "Environment name")
    var env: String

    @Flag(name: .shortAndLong, help: "Show secret values")
    var showSecrets: Bool = false

    @MainActor
    func run() async throws {
        let store = DataStore.shared
        let projectName = try resolveProjectName(project)

        guard let proj = try store.getProject(name: projectName) else {
            print("Error: Project '\(projectName)' not found.")
            throw ExitCode.failure
        }

        let envName = resolveEnvName(env, in: proj)
        guard let environment = store.getEnvironment(name: envName, in: proj) else {
            print("Error: Environment '\(env)' not found in '\(projectName)'.")
            throw ExitCode.failure
        }

        let variables = store.listVariables(in: environment, project: proj)

        if variables.isEmpty {
            print("No variables in '\(projectName)/\(envName)'.")
            print("Add one with: keyva var set KEY value --env \"\(envName)\"")
            return
        }

        print("Variables in '\(projectName)/\(envName)' (\(variables.count)):")
        for variable in variables {
            var value: String
            if variable.isSecret {
                if showSecrets {
                    value = (try? await store.keychain.retrieve(for: variable.id)) ?? "[ERROR]"
                } else {
                    value = "[SECRET]"
                }
            } else {
                value = variable.value
            }

            let secretBadge = variable.isSecret ? " 🔒" : ""
            let sharedBadge = variable.isShared ? " (shared)" : ""
            print("  \(variable.key)=\(value)\(secretBadge)\(sharedBadge)")
        }
    }
}

struct VarSet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set a variable"
    )

    @Argument(help: "Variable key")
    var key: String

    @Argument(help: "Variable value")
    var value: String

    @Option(name: .shortAndLong, help: "Project name (optional if directory is linked)")
    var project: String?

    @Option(name: .shortAndLong, help: "Environment name")
    var env: String

    @Flag(name: .shortAndLong, help: "Mark as secret (stored securely)")
    var secret: Bool = false

    @Option(name: .shortAndLong, help: "Optional notes")
    var notes: String?

    @MainActor
    func run() async throws {
        let store = DataStore.shared
        let projectName = try resolveProjectName(project)

        guard let proj = try store.getProject(name: projectName) else {
            print("Error: Project '\(projectName)' not found.")
            throw ExitCode.failure
        }

        let envName = resolveEnvName(env, in: proj)
        guard let environment = store.getEnvironment(name: envName, in: proj) else {
            print("Error: Environment '\(env)' not found in '\(projectName)'.")
            throw ExitCode.failure
        }

        _ = try await store.setVariable(
            key: key,
            value: value,
            isSecret: secret,
            notes: notes,
            in: [environment],
            project: proj
        )

        let secretNote = secret ? " (secret)" : ""
        print("✓ Set \(key)=\(secret ? "[SECRET]" : value)\(secretNote) in '\(projectName)/\(envName)'")
    }
}

struct VarGet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Get a variable value"
    )

    @Argument(help: "Variable key")
    var key: String

    @Option(name: .shortAndLong, help: "Project name (optional if directory is linked)")
    var project: String?

    @Option(name: .shortAndLong, help: "Environment name")
    var env: String

    @MainActor
    func run() async throws {
        let store = DataStore.shared
        let projectName = try resolveProjectName(project)

        guard let proj = try store.getProject(name: projectName) else {
            print("Error: Project '\(projectName)' not found.")
            throw ExitCode.failure
        }

        let envName = resolveEnvName(env, in: proj)
        guard let environment = store.getEnvironment(name: envName, in: proj) else {
            print("Error: Environment '\(env)' not found in '\(projectName)'.")
            throw ExitCode.failure
        }

        guard let variable = store.getVariable(key: key, in: environment, project: proj) else {
            print("Error: Variable '\(key)' not found in '\(projectName)/\(envName)'.")
            throw ExitCode.failure
        }

        let value: String
        if variable.isSecret {
            value = (try? await store.keychain.retrieve(for: variable.id)) ?? "[ERROR]"
        } else {
            value = variable.value
        }

        // Output just the value for easy piping
        print(value)
    }
}

struct VarDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a variable"
    )

    @Argument(help: "Variable key")
    var key: String

    @Option(name: .shortAndLong, help: "Project name (optional if directory is linked)")
    var project: String?

    @Option(name: .shortAndLong, help: "Environment name")
    var env: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force: Bool = false

    @MainActor
    func run() async throws {
        let store = DataStore.shared
        let projectName = try resolveProjectName(project)

        guard let proj = try store.getProject(name: projectName) else {
            print("Error: Project '\(projectName)' not found.")
            throw ExitCode.failure
        }

        let envName = resolveEnvName(env, in: proj)
        guard let environment = store.getEnvironment(name: envName, in: proj) else {
            print("Error: Environment '\(env)' not found in '\(projectName)'.")
            throw ExitCode.failure
        }

        guard let variable = store.getVariable(key: key, in: environment, project: proj) else {
            print("Error: Variable '\(key)' not found in '\(projectName)/\(envName)'.")
            throw ExitCode.failure
        }

        if !force {
            print("Delete variable '\(key)' from '\(projectName)/\(envName)'? [y/N] ", terminator: "")
            guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
                print("Cancelled.")
                return
            }
        }

        try await store.deleteVariable(variable)
        print("✓ Deleted variable '\(key)' from '\(projectName)/\(envName)'")
    }
}

// MARK: - Export Command

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export variables to a file"
    )

    @Argument(help: "Environment name (e.g., 'prod', 'dev', 'staging')")
    var env: String?

    @Option(name: .shortAndLong, help: "Project name (optional if directory is linked)")
    var project: String?

    @Option(name: .shortAndLong, help: "Output format (env, json, yaml, xcconfig)")
    var format: String = "env"

    @Option(name: .shortAndLong, help: "Output file (default: .env in current directory)")
    var output: String?

    @Flag(name: .long, help: "Include secret values in output")
    var includeSecrets: Bool = false

    @Flag(name: .long, help: "Print to stdout instead of file")
    var stdout: Bool = false

    @MainActor
    func run() async throws {
        let store = DataStore.shared
        let linkService = LinkService.shared
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        // Resolve project name
        let projectName: String
        if let p = project {
            projectName = p
        } else if let link = linkService.getLink(for: currentDir) {
            projectName = link.projectName
        } else {
            print("Error: No project specified and current directory is not linked.")
            print("Use --project or run 'keyva link <project>' first.")
            throw ExitCode.failure
        }

        guard let proj = try store.getProject(name: projectName) else {
            print("Error: Project '\(projectName)' not found.")
            throw ExitCode.failure
        }

        // Resolve environment name
        let envName: String
        if let e = env {
            envName = resolveEnvName(e, in: proj)
        } else if let link = linkService.getLink(for: currentDir), let defaultEnv = link.defaultEnvironment {
            envName = defaultEnv
        } else {
            print("Error: No environment specified.")
            print("Use: keyva export <env> (e.g., keyva export prod)")
            throw ExitCode.failure
        }

        guard let environment = store.getEnvironment(name: envName, in: proj) else {
            print("Error: Environment '\(envName)' not found in '\(projectName)'.")
            print("Available: \((proj.groups ?? []).map { $0.name }.joined(separator: ", "))")
            throw ExitCode.failure
        }

        // Parse format
        let exportFormat: ExportFormat
        switch format.lowercased() {
        case "env", ".env", "dotenv":
            exportFormat = .dotenv
        case "json":
            exportFormat = .json
        case "yaml", "yml":
            exportFormat = .yaml
        case "xcconfig":
            exportFormat = .xcconfig
        default:
            print("Error: Unknown format '\(format)'. Use: env, json, yaml, or xcconfig")
            throw ExitCode.failure
        }

        // Get content
        let content = await store.export(
            project: proj,
            env: environment,
            format: exportFormat,
            includeSecrets: includeSecrets
        )

        // Output
        if stdout {
            print(content)
        } else {
            let outputPath = output ?? defaultOutputPath(for: exportFormat)
            let url = URL(fileURLWithPath: outputPath)
            try content.write(to: url, atomically: true, encoding: .utf8)
            print("✓ Exported \(projectName)/\(envName) to \(outputPath)")
        }
    }

    private func defaultOutputPath(for format: ExportFormat) -> String {
        switch format {
        case .dotenv: return ".env"
        case .json: return "env.json"
        case .yaml: return "env.yaml"
        case .xcconfig: return "Config.xcconfig"
        }
    }
}

// MARK: - Link Command

struct LinkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "link",
        abstract: "Link current directory to a project",
        subcommands: [
            LinkSet.self,
            LinkRemove.self,
            LinkShow.self,
            LinkList.self,
        ],
        defaultSubcommand: LinkSet.self
    )
}

struct LinkSet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Link current directory to a project"
    )

    @Argument(help: "Project name to link")
    var project: String

    @Option(name: .shortAndLong, help: "Default environment for exports")
    var defaultEnv: String?

    @Flag(name: .long, help: "Store link globally (not in .keyva file)")
    var global: Bool = false

    @MainActor
    func run() async throws {
        let store = DataStore.shared
        let linkService = LinkService.shared
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        // Verify project exists
        guard let proj = try store.getProject(name: project) else {
            print("Error: Project '\(project)' not found.")
            print("Available projects:")
            for p in try store.listProjects() {
                print("  • \(p.name)")
            }
            throw ExitCode.failure
        }

        // Verify default env exists if specified
        if let envName = defaultEnv {
            let resolved = resolveEnvName(envName, in: proj)
            guard store.getEnvironment(name: resolved, in: proj) != nil else {
                print("Error: Environment '\(envName)' not found in '\(project)'.")
                throw ExitCode.failure
            }
        }

        if global {
            try linkService.addGlobalLink(directory: currentDir, to: project, defaultEnv: defaultEnv)
            print("✓ Linked '\(currentDir.lastPathComponent)' → '\(project)' (global)")
        } else {
            try linkService.link(directory: currentDir, to: project, defaultEnv: defaultEnv)
            print("✓ Linked '\(currentDir.lastPathComponent)' → '\(project)'")
            print("  Created .keyva file (add to .gitignore)")
        }

        if let env = defaultEnv {
            print("  Default environment: \(env)")
        }

        print("\nNow you can use:")
        print("  keyva export prod        # Export Production to .env")
        print("  keyva export dev         # Export Development to .env")
        print("  keyva var list --env prod")
    }
}

struct LinkRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove link from current directory"
    )

    @Flag(name: .long, help: "Remove global link")
    var global: Bool = false

    func run() throws {
        let linkService = LinkService.shared
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        if global {
            try linkService.removeGlobalLink(for: currentDir)
            print("✓ Removed global link for '\(currentDir.lastPathComponent)'")
        } else {
            try linkService.unlink(directory: currentDir)
            print("✓ Removed link (deleted .keyva file)")
        }
    }
}

struct LinkShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show current directory link"
    )

    func run() {
        let linkService = LinkService.shared
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        if let link = linkService.getLink(for: currentDir) {
            print("Current directory linked to:")
            print("  Project: \(link.projectName)")
            if let env = link.defaultEnvironment {
                print("  Default env: \(env)")
            }
        } else {
            print("Current directory is not linked to any project.")
            print("Use 'keyva link <project>' to link.")
        }
    }
}

struct LinkList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all global links"
    )

    func run() {
        let linkService = LinkService.shared
        let links = linkService.listGlobalLinks()

        if links.isEmpty {
            print("No global links configured.")
            return
        }

        print("Global links:")
        for (path, config) in links.sorted(by: { $0.key < $1.key }) {
            let envInfo = config.defaultEnvironment.map { " (default: \($0))" } ?? ""
            print("  \(path) → \(config.projectName)\(envInfo)")
        }
    }
}

// MARK: - Pull Command (shorthand for export)

struct PullCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Quick export: keyva pull prod → exports .env"
    )

    @Argument(help: "Environment name (prod, dev, staging)")
    var env: String

    @Flag(name: .long, help: "Include secret values")
    var secrets: Bool = false

    @MainActor
    func run() async throws {
        let store = DataStore.shared
        let linkService = LinkService.shared
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        guard let link = linkService.getLink(for: currentDir) else {
            print("Error: Current directory is not linked to a project.")
            print("Use 'keyva link <project>' first.")
            throw ExitCode.failure
        }

        guard let proj = try store.getProject(name: link.projectName) else {
            print("Error: Linked project '\(link.projectName)' not found.")
            throw ExitCode.failure
        }

        let envName = resolveEnvName(env, in: proj)
        guard let environment = store.getEnvironment(name: envName, in: proj) else {
            print("Error: Environment '\(env)' not found.")
            print("Available: \((proj.groups ?? []).map { $0.name }.joined(separator: ", "))")
            throw ExitCode.failure
        }

        let content = await store.export(
            project: proj,
            env: environment,
            format: .dotenv,
            includeSecrets: secrets
        )

        let outputPath = ".env"
        try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
        print("✓ Pulled \(link.projectName)/\(envName) → .env")
    }
}

// MARK: - Helpers

/// Resolve project name from argument or link
func resolveProjectName(_ projectArg: String?) throws -> String {
    if let name = projectArg {
        return name
    }

    let linkService = LinkService.shared
    let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    if let link = linkService.getLink(for: currentDir) {
        return link.projectName
    }

    print("Error: No project specified and current directory is not linked.")
    print("Use --project or run 'keyva link <project>' first.")
    throw ExitCode.failure
}

/// Resolve environment alias to actual name
func resolveEnvName(_ alias: String, in project: Project) -> String {
    let linkService = LinkService.shared

    if let resolved = linkService.resolveEnvironmentName(alias, in: project) {
        return resolved
    }

    // Return as-is if not found (will error later)
    return alias
}
