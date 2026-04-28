import Foundation
import OSLog

private let appPathsLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "AppPaths")

struct AppPaths {
    let appSupportDirectory: URL
    let accountsFile: URL
    let snapshotsDirectory: URL
    let codexAuthFile: URL

    private static let appSupportFolderName = "CodexPill"
    private static let legacyAppSupportFolderName = "CodexSwitchboard"

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let targetDirectory: URL
        let legacyDirectory: URL?
        let isolatedAuthRootDirectory: URL?
        if let overrideDirectory = AppRuntimeEnvironment.validationAppSupportDirectory(environment: environment) {
            targetDirectory = overrideDirectory
            legacyDirectory = nil
            isolatedAuthRootDirectory = overrideDirectory
        } else if let testDirectory = AppRuntimeEnvironment.automatedTestAppSupportDirectory(environment: environment) {
            targetDirectory = testDirectory
            legacyDirectory = nil
            isolatedAuthRootDirectory = testDirectory
        } else {
            let supportRoot = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            targetDirectory = supportRoot.appendingPathComponent(Self.appSupportFolderName, isDirectory: true)
            legacyDirectory = supportRoot.appendingPathComponent(Self.legacyAppSupportFolderName, isDirectory: true)
            isolatedAuthRootDirectory = nil
        }

        if let legacyDirectory,
           !fileManager.fileExists(atPath: targetDirectory.path),
           fileManager.fileExists(atPath: legacyDirectory.path) {
            appPathsLogger.log("Migrating app support directory from legacy path")
            try fileManager.moveItem(at: legacyDirectory, to: targetDirectory)
        }

        appSupportDirectory = targetDirectory
        accountsFile = appSupportDirectory.appendingPathComponent("accounts.json")
        snapshotsDirectory = appSupportDirectory.appendingPathComponent("snapshots", isDirectory: true)
        if let isolatedAuthRootDirectory {
            codexAuthFile = isolatedAuthRootDirectory
                .appendingPathComponent("auth.json")
        } else {
            codexAuthFile = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("auth.json")
        }

        let resolvedAppSupportPath = appSupportDirectory.path
        let resolvedAccountsPath = accountsFile.path
        let resolvedSnapshotsPath = snapshotsDirectory.path
        let resolvedAuthPath = codexAuthFile.path
        appPathsLogger.log("Resolved app support directory: \(resolvedAppSupportPath, privacy: .public)")
        appPathsLogger.log("Resolved accounts file: \(resolvedAccountsPath, privacy: .public)")
        appPathsLogger.log("Resolved snapshots directory: \(resolvedSnapshotsPath, privacy: .public)")
        appPathsLogger.log("Resolved auth file: \(resolvedAuthPath, privacy: .public)")
    }
}

struct IsolatedCodexHomeSession {
    private static let directoryPrefix = "CodexPill-CODEX_HOME-"

    let rootDirectory: URL
    let authFile: URL
    let configFile: URL
    let tempDirectory: URL

    static func create(
        fileManager: FileManager = .default,
        parentDirectory: URL? = nil
    ) throws -> IsolatedCodexHomeSession {
        let baseDirectory = parentDirectory ?? fileManager.temporaryDirectory
        let rootDirectory = baseDirectory
            .appendingPathComponent("\(directoryPrefix)\(UUID().uuidString)", isDirectory: true)
        let tempDirectory = rootDirectory.appendingPathComponent("tmp", isDirectory: true)

        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        return IsolatedCodexHomeSession(
            rootDirectory: rootDirectory,
            authFile: rootDirectory.appendingPathComponent("auth.json"),
            configFile: rootDirectory.appendingPathComponent("config.toml"),
            tempDirectory: tempDirectory
        )
    }

    func cleanup(fileManager: FileManager = .default) throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
        try fileManager.removeItem(at: rootDirectory)
    }

    static func cleanupStaleSessions(
        olderThan age: TimeInterval = 24 * 60 * 60,
        fileManager: FileManager = .default,
        parentDirectory: URL? = nil,
        now: Date = Date()
    ) throws {
        let baseDirectory = parentDirectory ?? fileManager.temporaryDirectory
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return }

        let entries = try fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
        )
        for entry in entries where entry.lastPathComponent.hasPrefix(directoryPrefix) {
            let values = try entry.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard values.isDirectory == true else { continue }
            let modifiedAt = values.contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(modifiedAt) >= age else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }
}
