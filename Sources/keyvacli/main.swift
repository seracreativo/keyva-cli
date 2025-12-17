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
        version: "1.0.0",
        subcommands: [
            ProjectCommand.self,
            EnvCommand.self,
            VarCommand.self,
            ExportCommand.self,
        ]
    )
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

    @Option(name: .shortAndLong, help: "Project name")
    var project: String

    @MainActor
    func run() async throws {
        let store = DataStore.shared

        guard let proj = try store.getProject(name: project) else {
            print("Error: Project '\(project)' not found.")
            throw ExitCode.failure
        }

        let envs = store.listEnvironments(in: proj)

        if envs.isEmpty {
            print("No environments in '\(project)'.")
            print("Create one with: keyva env create \"dev\" --project \"\(project)\"")
            return
        }

        print("Environments in '\(project)' (\(envs.count)):")
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

    @Argument(help: "Environment name")
    var name: String

    @Option(name: .shortAndLong, help: "Project name")
    var project: String

    @Option(name: .shortAndLong, help: "SF Symbol icon name")
    var icon: String = "folder.fill"

    @MainActor
    func run() async throws {
        let store = DataStore.shared

        guard let proj = try store.getProject(name: project) else {
            print("Error: Project '\(project)' not found.")
            throw ExitCode.failure
        }

        // Check if env already exists
        if let _ = store.getEnvironment(name: name, in: proj) {
            print("Error: Environment '\(name)' already exists in '\(project)'.")
            throw ExitCode.failure
        }

        // Suggest icon based on name
        let suggestedIcons = EnvironmentGroup.suggestIcons(for: name)
        let finalIcon = icon == "folder.fill" ? suggestedIcons.first ?? icon : icon

        let env = try store.createEnvironment(name: name, icon: finalIcon, in: proj)
        print("✓ Created environment '\(env.name)' in '\(project)'")
    }
}

struct EnvDelete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete an environment"
    )

    @Argument(help: "Environment name")
    var name: String

    @Option(name: .shortAndLong, help: "Project name")
    var project: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force: Bool = false

    @MainActor
    func run() async throws {
        let store = DataStore.shared

        guard let proj = try store.getProject(name: project) else {
            print("Error: Project '\(project)' not found.")
            throw ExitCode.failure
        }

        guard let env = store.getEnvironment(name: name, in: proj) else {
            print("Error: Environment '\(name)' not found in '\(project)'.")
            throw ExitCode.failure
        }

        if !force {
            print("Delete environment '\(name)' from '\(project)'? [y/N] ", terminator: "")
            guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
                print("Cancelled.")
                return
            }
        }

        try await store.deleteEnvironment(env, in: proj)
        print("✓ Deleted environment '\(name)' from '\(project)'")
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

    @Option(name: .shortAndLong, help: "Project name")
    var project: String

    @Option(name: .shortAndLong, help: "Environment name")
    var env: String

    @Flag(name: .shortAndLong, help: "Show secret values")
    var showSecrets: Bool = false

    @MainActor
    func run() async throws {
        let store = DataStore.shared

        guard let proj = try store.getProject(name: project) else {
            print("Error: Project '\(project)' not found.")
            throw ExitCode.failure
        }

        guard let environment = store.getEnvironment(name: env, in: proj) else {
            print("Error: Environment '\(env)' not found in '\(project)'.")
            throw ExitCode.failure
        }

        let variables = store.listVariables(in: environment, project: proj)

        if variables.isEmpty {
            print("No variables in '\(project)/\(env)'.")
            print("Add one with: keyva var set KEY value --project \"\(project)\" --env \"\(env)\"")
            return
        }

        print("Variables in '\(project)/\(env)' (\(variables.count)):")
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

    @Option(name: .shortAndLong, help: "Project name")
    var project: String

    @Option(name: .shortAndLong, help: "Environment name")
    var env: String

    @Flag(name: .shortAndLong, help: "Mark as secret (stored in Keychain)")
    var secret: Bool = false

    @Option(name: .shortAndLong, help: "Optional notes")
    var notes: String?

    @MainActor
    func run() async throws {
        let store = DataStore.shared

        guard let proj = try store.getProject(name: project) else {
            print("Error: Project '\(project)' not found.")
            throw ExitCode.failure
        }

        guard let environment = store.getEnvironment(name: env, in: proj) else {
            print("Error: Environment '\(env)' not found in '\(project)'.")
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
        print("✓ Set \(key)=\(secret ? "[SECRET]" : value)\(secretNote) in '\(project)/\(env)'")
    }
}

struct VarGet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Get a variable value"
    )

    @Argument(help: "Variable key")
    var key: String

    @Option(name: .shortAndLong, help: "Project name")
    var project: String

    @Option(name: .shortAndLong, help: "Environment name")
    var env: String

    @MainActor
    func run() async throws {
        let store = DataStore.shared

        guard let proj = try store.getProject(name: project) else {
            print("Error: Project '\(project)' not found.")
            throw ExitCode.failure
        }

        guard let environment = store.getEnvironment(name: env, in: proj) else {
            print("Error: Environment '\(env)' not found in '\(project)'.")
            throw ExitCode.failure
        }

        guard let variable = store.getVariable(key: key, in: environment, project: proj) else {
            print("Error: Variable '\(key)' not found in '\(project)/\(env)'.")
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

    @Option(name: .shortAndLong, help: "Project name")
    var project: String

    @Option(name: .shortAndLong, help: "Environment name")
    var env: String

    @Flag(name: .shortAndLong, help: "Skip confirmation prompt")
    var force: Bool = false

    @MainActor
    func run() async throws {
        let store = DataStore.shared

        guard let proj = try store.getProject(name: project) else {
            print("Error: Project '\(project)' not found.")
            throw ExitCode.failure
        }

        guard let environment = store.getEnvironment(name: env, in: proj) else {
            print("Error: Environment '\(env)' not found in '\(project)'.")
            throw ExitCode.failure
        }

        guard let variable = store.getVariable(key: key, in: environment, project: proj) else {
            print("Error: Variable '\(key)' not found in '\(project)/\(env)'.")
            throw ExitCode.failure
        }

        if !force {
            print("Delete variable '\(key)' from '\(project)/\(env)'? [y/N] ", terminator: "")
            guard let response = readLine()?.lowercased(), response == "y" || response == "yes" else {
                print("Cancelled.")
                return
            }
        }

        try await store.deleteVariable(variable)
        print("✓ Deleted variable '\(key)' from '\(project)/\(env)'")
    }
}

// MARK: - Export Command

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export variables to a file"
    )

    @Option(name: .shortAndLong, help: "Project name")
    var project: String

    @Option(name: .shortAndLong, help: "Environment name")
    var env: String

    @Option(name: .shortAndLong, help: "Output format (env, json, yaml, xcconfig)")
    var format: String = "env"

    @Option(name: .shortAndLong, help: "Output file (default: stdout)")
    var output: String?

    @Flag(name: .long, help: "Include secret values in output")
    var includeSecrets: Bool = false

    @MainActor
    func run() async throws {
        let store = DataStore.shared

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
        let content: String
        do {
            content = try await store.exportByName(
                projectName: project,
                envName: env,
                format: exportFormat,
                includeSecrets: includeSecrets
            )
        } catch let error as DataStoreError {
            print("Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        // Output
        if let outputPath = output {
            let url = URL(fileURLWithPath: outputPath)
            try content.write(to: url, atomically: true, encoding: .utf8)
            print("✓ Exported to \(outputPath)")
        } else {
            print(content)
        }
    }
}
