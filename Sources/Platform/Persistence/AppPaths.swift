import Foundation
import OSLog

private let appPathsLogger = Logger(subsystem: "com.raphhgg.rusage", category: "AppPaths")

struct AppPaths {
    let appSupportDirectory: URL
    let codexAuthFile: URL

    static let appSupportFolderName = "rusage"
    private static let legacyAppSupportFolderName = "CodexSwitchboard"

    init(
        isolatedRootDirectory: URL?,
        fileManager: FileManager = .default
    ) throws {
        let targetDirectory: URL
        let legacyDirectory: URL?
        if let isolatedRootDirectory {
            targetDirectory = isolatedRootDirectory
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
        if let isolatedRootDirectory {
            codexAuthFile = isolatedRootDirectory
                .appendingPathComponent("auth.json")
        } else {
            codexAuthFile = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("auth.json")
        }

        let resolvedAppSupportPath = appSupportDirectory.path
        let resolvedAuthPath = codexAuthFile.path
        appPathsLogger.log("Resolved app support directory: \(resolvedAppSupportPath, privacy: .public)")
        appPathsLogger.log("Resolved auth file: \(resolvedAuthPath, privacy: .public)")
    }

    static func tokenUsageCacheFile(
        isolatedRootDirectory: URL?,
        fileManager: FileManager = .default
    ) -> URL {
        let cacheDirectory: URL
        if let isolatedRootDirectory {
            cacheDirectory = isolatedRootDirectory.appendingPathComponent("Caches", isDirectory: true)
        } else {
            let cachesRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            cacheDirectory = cachesRoot.appendingPathComponent(appSupportFolderName, isDirectory: true)
        }
        return cacheDirectory.appendingPathComponent("token-usage-cache.json")
    }
}

struct IsolatedCodexHomeSession {
    private static let directoryPrefix = "rusage-CODEX_HOME-"

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
