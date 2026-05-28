import Foundation

struct AccountRepository: @unchecked Sendable {
    private let fileManager: FileManager
    let paths: AppPaths

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        self.fileManager = fileManager
        self.paths = try AppPaths(fileManager: fileManager, environment: environment)
    }

    func bootstrapStorage() throws {
        try FilePermissionHardening.createPrivateDirectory(
            at: paths.appSupportDirectory,
            fileManager: fileManager
        )
        try FilePermissionHardening.createPrivateDirectory(
            at: paths.snapshotsDirectory,
            fileManager: fileManager
        )

        if fileManager.fileExists(atPath: paths.accountsFile.path) {
            try FilePermissionHardening.repairPrivateFile(at: paths.accountsFile, fileManager: fileManager)
        } else {
            try saveAccounts([])
        }
        try repairSavedSnapshotFiles()
    }

    func loadAccounts() throws -> [CodexAccount] {
        guard fileManager.fileExists(atPath: paths.accountsFile.path) else { return [] }
        let data = try Data(contentsOf: paths.accountsFile)
        return try Self.makeDecoder().decode([CodexAccount].self, from: data)
    }

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        let data = try Self.makeEncoder().encode(accounts)
        try data.write(to: paths.accountsFile, options: .atomic)
        try FilePermissionHardening.repairPrivateFile(at: paths.accountsFile, fileManager: fileManager)
    }

    func snapshotURL(for account: CodexAccount) -> URL {
        paths.snapshotsDirectory.appendingPathComponent(account.snapshotFileName)
    }

    func writeSnapshot(data: Data, for account: CodexAccount) throws {
        let url = snapshotURL(for: account)
        try data.write(to: url, options: .atomic)
        try FilePermissionHardening.repairPrivateFile(at: url, fileManager: fileManager)
    }

    func readSnapshot(for account: CodexAccount) throws -> Data {
        let url = snapshotURL(for: account)
        try FilePermissionHardening.repairPrivateFile(at: url, fileManager: fileManager)
        return try Data(contentsOf: url)
    }

    func deleteSnapshot(for account: CodexAccount) throws {
        let url = snapshotURL(for: account)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func repairSavedSnapshotFiles() throws {
        guard fileManager.fileExists(atPath: paths.snapshotsDirectory.path) else { return }
        let entries = try fileManager.contentsOfDirectory(
            at: paths.snapshotsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            try FilePermissionHardening.repairPrivateFile(at: entry, fileManager: fileManager)
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
