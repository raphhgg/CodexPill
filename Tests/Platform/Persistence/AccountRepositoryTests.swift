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

    @Test
    func accountsFileWrittenBeforeUsageWindowsLoadsAsUsageAndSavesInTheSameShape() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try makeRepository(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(Self.accountsFileBeforeUsageWindows.utf8).write(to: repository.paths.accountsFile)

        let account = try #require(try repository.loadAccounts().first)

        #expect(account.planType == "plus")
        #expect(account.effectivePlanType == "pro")
        #expect(account.usage == UsageSnapshot(
            provider: .codex,
            planName: "pro",
            windows: [
                UsageWindow(
                    kind: .session,
                    usedPercent: 42,
                    resetsAt: Date(timeIntervalSince1970: 1_800_010_000),
                    durationMinutes: 300
                ),
                UsageWindow(
                    kind: .weekly,
                    usedPercent: 68,
                    resetsAt: Date(timeIntervalSince1970: 1_800_400_000),
                    durationMinutes: 10_080
                ),
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_200)
        ))

        try repository.saveAccounts([account])

        #expect(try repository.loadAccounts() == [account])
        let saved = try String(contentsOf: repository.paths.accountsFile, encoding: .utf8)
        #expect(saved == Self.accountsFileBeforeUsageWindows.replacingOccurrences(of: "      \"limitID\" : \"codex\",\n", with: ""))
    }

    private static let accountsFileBeforeUsageWindows = """
    [
      {
        "createdAt" : "2027-01-15T08:00:00Z",
        "email" : "work@example.com",
        "id" : "11111111-2222-3333-4444-555555555555",
        "identity" : {
          "remoteIdentity" : {
            "normalizedEmailAddress" : "work@example.com"
          },
          "snapshotFingerprint" : "fp-fake",
          "stableAccountID" : "acct-fake"
        },
        "name" : "Work",
        "planType" : "plus",
        "rateLimits" : {
          "fetchedAt" : "2027-01-15T08:03:20Z",
          "limitID" : "codex",
          "planType" : "pro",
          "primary" : {
            "resetsAt" : "2027-01-15T10:46:40Z",
            "usedPercent" : 42,
            "windowDurationMinutes" : 300
          },
          "secondary" : {
            "resetsAt" : "2027-01-19T23:06:40Z",
            "usedPercent" : 68,
            "windowDurationMinutes" : 10080
          }
        },
        "snapshotFileName" : "11111111-2222-3333-4444-555555555555.json",
        "updatedAt" : "2027-01-15T08:01:40Z"
      }
    ]
    """

    private func makeRepository(root: URL) throws -> AccountRepository {
        try AccountRepository(
            isolatedRootDirectory: root
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
