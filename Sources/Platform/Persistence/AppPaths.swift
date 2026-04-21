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
        if let overrideDirectory = AppRuntimeEnvironment.validationAppSupportDirectory(environment: environment) {
            targetDirectory = overrideDirectory
            legacyDirectory = nil
        } else {
            let supportRoot = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            targetDirectory = supportRoot.appendingPathComponent(Self.appSupportFolderName, isDirectory: true)
            legacyDirectory = supportRoot.appendingPathComponent(Self.legacyAppSupportFolderName, isDirectory: true)
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
        codexAuthFile = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")

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
