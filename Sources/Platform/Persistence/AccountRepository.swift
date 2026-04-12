import Foundation

struct AccountRepository {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    let paths: AppPaths

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.paths = try AppPaths(fileManager: fileManager)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func bootstrapStorage() throws {
        try fileManager.createDirectory(at: paths.appSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.snapshotsDirectory, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: paths.accountsFile.path) else { return }
        try saveAccounts([])
    }

    func loadAccounts() throws -> [CodexAccount] {
        guard fileManager.fileExists(atPath: paths.accountsFile.path) else { return [] }
        let data = try Data(contentsOf: paths.accountsFile)
        return try decoder.decode([CodexAccount].self, from: data)
    }

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        let data = try encoder.encode(accounts)
        try data.write(to: paths.accountsFile, options: .atomic)
    }

    func snapshotURL(for account: CodexAccount) -> URL {
        paths.snapshotsDirectory.appendingPathComponent(account.snapshotFileName)
    }

    func writeSnapshot(data: Data, for account: CodexAccount) throws {
        try data.write(to: snapshotURL(for: account), options: .atomic)
    }

    func readSnapshot(for account: CodexAccount) throws -> Data {
        try Data(contentsOf: snapshotURL(for: account))
    }

    func deleteSnapshot(for account: CodexAccount) throws {
        let url = snapshotURL(for: account)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
