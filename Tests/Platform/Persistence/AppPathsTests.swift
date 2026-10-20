import Foundation
import Testing

@testable import RUsage

struct AppPathsTests {
    @Test
    func isolatedRootDirectoryBypassesDefaultApplicationSupportLocation() throws {
        let overrideDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = try AppPaths(
            isolatedRootDirectory: overrideDirectory
        )

        #expect(normalizedDirectoryPath(paths.appSupportDirectory) == normalizedDirectoryPath(overrideDirectory))
        #expect(
            paths.accountsFile.standardizedFileURL.path
                == overrideDirectory.appendingPathComponent("accounts.json").standardizedFileURL.path
        )
        #expect(
            normalizedDirectoryPath(paths.snapshotsDirectory)
                == normalizedDirectoryPath(overrideDirectory.appendingPathComponent("snapshots", isDirectory: true))
        )
        #expect(
            paths.codexAuthFile.standardizedFileURL.path
                == overrideDirectory
                .appendingPathComponent("auth.json")
                .standardizedFileURL.path
        )
    }

    @Test
    func tokenUsageCacheStaysInsideIsolatedRootDirectory() {
        let isolatedRootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let cacheFile = AppPaths.tokenUsageCacheFile(isolatedRootDirectory: isolatedRootDirectory)

        #expect(
            cacheFile.standardizedFileURL.path
                == isolatedRootDirectory.appendingPathComponent("Caches/token-usage-cache.json").standardizedFileURL.path
        )
    }

    @Test
    func isolatedCodexHomeSessionUsesRootLevelAuthPathAndCreatesMinimalLayout() throws {
        let parentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parentDirectory) }

        let session = try IsolatedCodexHomeSession.create(
            fileManager: .default,
            parentDirectory: parentDirectory
        )

        #expect(session.rootDirectory.deletingLastPathComponent().standardizedFileURL.path == parentDirectory.standardizedFileURL.path)
        #expect(session.authFile.standardizedFileURL.path == session.rootDirectory.appendingPathComponent("auth.json").standardizedFileURL.path)
        #expect(session.configFile.standardizedFileURL.path == session.rootDirectory.appendingPathComponent("config.toml").standardizedFileURL.path)
        #expect(FileManager.default.fileExists(atPath: session.rootDirectory.path))
        #expect(FileManager.default.fileExists(atPath: session.tempDirectory.path))
    }

    @Test
    func isolatedCodexHomeSessionCleanupRemovesRootDirectory() throws {
        let parentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parentDirectory) }

        let session = try IsolatedCodexHomeSession.create(
            fileManager: .default,
            parentDirectory: parentDirectory
        )
        let markerFile = session.rootDirectory.appendingPathComponent("marker.txt")
        try Data("marker".utf8).write(to: markerFile)

        try session.cleanup(fileManager: .default)

        #expect(!FileManager.default.fileExists(atPath: session.rootDirectory.path))
    }

    @Test
    func staleIsolatedCodexHomeCleanupRemovesOnlyOldSessionDirectories() throws {
        let parentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parentDirectory) }

        let staleSession = try IsolatedCodexHomeSession.create(
            fileManager: .default,
            parentDirectory: parentDirectory
        )
        let freshSession = try IsolatedCodexHomeSession.create(
            fileManager: .default,
            parentDirectory: parentDirectory
        )
        let unrelatedDirectory = parentDirectory.appendingPathComponent("Other-CODEX_HOME-old", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelatedDirectory, withIntermediateDirectories: true)

        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-48 * 60 * 60)],
            ofItemAtPath: staleSession.rootDirectory.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: freshSession.rootDirectory.path
        )

        try IsolatedCodexHomeSession.cleanupStaleSessions(
            olderThan: 24 * 60 * 60,
            fileManager: .default,
            parentDirectory: parentDirectory,
            now: now
        )

        #expect(!FileManager.default.fileExists(atPath: staleSession.rootDirectory.path))
        #expect(FileManager.default.fileExists(atPath: freshSession.rootDirectory.path))
        #expect(FileManager.default.fileExists(atPath: unrelatedDirectory.path))
    }

    private func normalizedDirectoryPath(_ url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
