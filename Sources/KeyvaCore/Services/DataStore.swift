//
//  DataStore.swift
//  KeyvaCore
//
//  Central data access layer for both App and CLI
//

import Foundation
import SwiftData

/// App Group identifier for shared data between app and CLI
public let appGroupIdentifier = "group.com.seracreativo.keyva"

/// Central data store for Keyva - provides unified access to projects, environments, and variables
@MainActor
public class DataStore {
    public static let shared = DataStore()

    public let container: ModelContainer
    public let keychain: KeychainService

    private init() {
        let schema = Schema([
            Project.self,
            EnvironmentGroup.self,
            Variable.self
        ])

        // Use App Group container for shared storage between app and CLI
        let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)

        let config: ModelConfiguration
        if let containerURL = containerURL {
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                groupContainer: .identifier(appGroupIdentifier),
                cloudKitDatabase: .automatic
            )
        } else {
            // Fallback for CLI or environments without App Group
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
        }

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        keychain = KeychainService.shared
    }

    /// Initialize with custom configuration (for testing)
    public init(inMemory: Bool = false, cloudKit: Bool = true, useAppGroup: Bool = true) {
        let schema = Schema([
            Project.self,
            EnvironmentGroup.self,
            Variable.self
        ])

        let config: ModelConfiguration
        if useAppGroup, let _ = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                groupContainer: .identifier(appGroupIdentifier),
                cloudKitDatabase: cloudKit ? .automatic : .none
            )
        } else {
            config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: cloudKit ? .automatic : .none
            )
        }

        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        keychain = KeychainService.shared
    }

    public var context: ModelContext {
        container.mainContext
    }

    // MARK: - Projects

    public func listProjects() throws -> [Project] {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }

    public func getProject(name: String) throws -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.name == name }
        )
        return try context.fetch(descriptor).first
    }

    public func getProject(id: UUID) throws -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    @discardableResult
    public func createProject(name: String, icon: String = "folder.fill") throws -> Project {
        let project = Project(name: name, icon: icon)
        context.insert(project)
        try context.save()
        return project
    }

    public func deleteProject(_ project: Project) async throws {
        // Delete all secrets from keychain first
        for variable in project.variables ?? [] where variable.isSecret {
            try? await keychain.delete(for: variable.id)
        }
        context.delete(project)
        try context.save()
    }

    // MARK: - Environments

    public func listEnvironments(in project: Project) -> [EnvironmentGroup] {
        (project.groups ?? []).sorted { $0.order < $1.order }
    }

    public func getEnvironment(name: String, in project: Project) -> EnvironmentGroup? {
        project.groups?.first { $0.name.lowercased() == name.lowercased() }
    }

    @discardableResult
    public func createEnvironment(name: String, icon: String = "folder.fill", in project: Project) throws -> EnvironmentGroup {
        let order = (project.groups?.count ?? 0)
        let env = EnvironmentGroup(name: name, icon: icon, order: order)
        env.project = project

        if project.groups == nil {
            project.groups = []
        }
        project.groups?.append(env)

        try context.save()
        return env
    }

    public func deleteEnvironment(_ env: EnvironmentGroup, in project: Project) async throws {
        // Update variables that reference this environment
        let variables = project.variables ?? []
        for variable in variables where variable.appliesTo(env.id) {
            var envs = variable.environments
            envs.remove(env.id)

            if envs.isEmpty {
                // Delete variable if no environments left
                if variable.isSecret {
                    try? await keychain.delete(for: variable.id)
                }
                context.delete(variable)
            } else {
                variable.setEnvironments(envs)
            }
        }

        context.delete(env)
        try context.save()
    }

    // MARK: - Variables

    public func listVariables(in env: EnvironmentGroup, project: Project) -> [Variable] {
        project.variables(for: env.id).sorted { $0.order < $1.order }
    }

    public func getVariable(key: String, in env: EnvironmentGroup, project: Project) -> Variable? {
        project.variables(for: env.id).first { $0.key == key }
    }

    @discardableResult
    public func setVariable(
        key: String,
        value: String,
        isSecret: Bool = false,
        notes: String? = nil,
        in envs: [EnvironmentGroup],
        project: Project
    ) async throws -> Variable {
        let envIDs = Set(envs.map { $0.id })

        // Check if variable already exists
        if let existing = project.variables?.first(where: { $0.key == key && !$0.environments.isDisjoint(with: envIDs) }) {
            // Update existing
            existing.setEnvironments(existing.environments.union(envIDs))

            if isSecret {
                existing.isSecret = true
                existing.value = "[SECURED]"
                try await keychain.save(value: value, for: existing.id)
            } else {
                existing.value = value
            }

            if let notes = notes {
                existing.notes = notes
            }

            try context.save()
            return existing
        }

        // Create new
        let order = (project.variables?.count ?? 0)
        let variable = Variable(
            key: key,
            value: value,
            isSecret: isSecret,
            notes: notes,
            order: order,
            environmentIDs: envIDs
        )
        variable.project = project

        if isSecret {
            try await keychain.save(value: value, for: variable.id)
        }

        if project.variables == nil {
            project.variables = []
        }
        project.variables?.append(variable)

        try context.save()
        return variable
    }

    public func deleteVariable(_ variable: Variable) async throws {
        if variable.isSecret {
            try? await keychain.delete(for: variable.id)
        }
        context.delete(variable)
        try context.save()
    }

    // MARK: - Migration

    /// Migrate existing secrets from Keychain to SecureStorage for CLI access
    /// Call this on app launch
    public func migrateSecretsForCLI() async {
        print("🔐 Starting secrets migration for CLI access...")
        do {
            let projects = try listProjects()
            var secretVariableIds: [UUID] = []

            for project in projects {
                let secretVars = (project.variables ?? []).filter { $0.isSecret }
                secretVariableIds.append(contentsOf: secretVars.map { $0.id })
            }

            print("🔐 Found \(secretVariableIds.count) secrets to check")

            if !secretVariableIds.isEmpty {
                try await keychain.migrateToSecureStorage(variableIds: secretVariableIds)
            } else {
                print("🔐 No secrets found to migrate")
            }
        } catch {
            print("⚠️ Secrets migration error: \(error)")
        }
    }

    // MARK: - Export

    public func export(
        project: Project,
        env: EnvironmentGroup,
        format: ExportFormat,
        includeSecrets: Bool
    ) async -> String {
        let variables = listVariables(in: env, project: project)
        return await EnvExporter.export(
            variables: variables,
            format: format,
            includeSecrets: includeSecrets,
            keychain: keychain
        )
    }

    public func exportByName(
        projectName: String,
        envName: String,
        format: ExportFormat,
        includeSecrets: Bool
    ) async throws -> String {
        guard let project = try getProject(name: projectName) else {
            throw DataStoreError.projectNotFound(projectName)
        }

        guard let env = getEnvironment(name: envName, in: project) else {
            throw DataStoreError.environmentNotFound(envName)
        }

        return await export(project: project, env: env, format: format, includeSecrets: includeSecrets)
    }
}

// MARK: - Errors

public enum DataStoreError: Error, LocalizedError {
    case projectNotFound(String)
    case environmentNotFound(String)
    case variableNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .projectNotFound(let name):
            return "Project '\(name)' not found"
        case .environmentNotFound(let name):
            return "Environment '\(name)' not found"
        case .variableNotFound(let key):
            return "Variable '\(key)' not found"
        }
    }
}
