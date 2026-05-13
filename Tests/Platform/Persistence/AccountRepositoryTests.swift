import Foundation
import Testing

@testable import CodexPill

struct AccountRepositoryTests {
    @Test
    func bootstrapStorageCreatesPrivateDirectoriesAndCatalogFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try makeRepository(root: root)

        try repository.bootstrapStorage()

        #expect(try posixPermissions(at: repository.paths.appSupportDirectory) == 0o700)
        #expect(try posixPermissions(at: repository.paths.snapshotsDirectory) == 0o700)
        #expect(try posixPermissions(at: repository.paths.accountsFile) == 0o600)
    }

    @Test
    func bootstrapStorageRepairsPermissiveDirectoriesAndCatalogFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = root.appendingPathComponent("snapshots", isDirectory: true)
        let accounts = root.appendingPathComponent("accounts.json")
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: accounts)
        try setPosixPermissions(0o755, at: root)
        try setPosixPermissions(0o755, at: snapshots)
        try setPosixPermissions(0o644, at: accounts)
        let repository = try makeRepository(root: root)

        try repository.bootstrapStorage()

        #expect(try posixPermissions(at: repository.paths.appSupportDirectory) == 0o700)
        #expect(try posixPermissions(at: repository.paths.snapshotsDirectory) == 0o700)
        #expect(try posixPermissions(at: repository.paths.accountsFile) == 0o600)
    }

    @Test
    func bootstrapStorageRepairsExistingSavedSnapshotFiles() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = root.appendingPathComponent("snapshots", isDirectory: true)
        let snapshot = snapshots.appendingPathComponent("research.json")
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try Data("existing fixture auth".utf8).write(to: snapshot)
        try setPosixPermissions(0o644, at: snapshot)
        let repository = try makeRepository(root: root)

        try repository.bootstrapStorage()

        #expect(try posixPermissions(at: snapshot) == 0o600)
    }

    @Test
    func writeSnapshotCreatesPrivateFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try makeRepository(root: root)
        let account = makeAccount()

        try repository.bootstrapStorage()
        try repository.writeSnapshot(data: Data("fixture auth".utf8), for: account)

        #expect(try posixPermissions(at: repository.snapshotURL(for: account)) == 0o600)
    }

    @Test
    func writeSnapshotRepairsPermissiveExistingFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try makeRepository(root: root)
        let account = makeAccount()

        try repository.bootstrapStorage()
        let snapshotURL = repository.snapshotURL(for: account)
        try Data("old fixture auth".utf8).write(to: snapshotURL)
        try setPosixPermissions(0o644, at: snapshotURL)
        try repository.writeSnapshot(data: Data("new fixture auth".utf8), for: account)

        #expect(try posixPermissions(at: snapshotURL) == 0o600)
    }

    @Test
    func readSnapshotRepairsPermissiveExistingFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try makeRepository(root: root)
        let account = makeAccount()

        try repository.bootstrapStorage()
        let snapshotURL = repository.snapshotURL(for: account)
        try Data("fixture auth".utf8).write(to: snapshotURL)
        try setPosixPermissions(0o644, at: snapshotURL)
        let data = try repository.readSnapshot(for: account)

        #expect(data == Data("fixture auth".utf8))
        #expect(try posixPermissions(at: snapshotURL) == 0o600)
    }

    private func makeRepository(root: URL) throws -> AccountRepository {
        try AccountRepository(
            fileManager: .default,
            environment: [AppRuntimeEnvironment.validationAppSupportDirectoryEnvironmentKey: root.path]
        )
    }

    private func makeAccount() -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: "Research",
            snapshotFileName: "research.json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            rateLimits: nil,
            identity: .empty
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        return try #require(value as? Int) & 0o777
    }

    private func setPosixPermissions(_ permissions: Int, at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }
}
