import Foundation
import SQLite3

final class CursorStateDatabaseHarness {
    let directoryURL: URL
    let databaseURL: URL
    private(set) var connection: OpaquePointer?

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorStateDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        databaseURL = directoryURL.appendingPathComponent("state.vscdb")
    }

    deinit {
        close()
        try? FileManager.default.removeItem(at: directoryURL)
    }

    func create(walMode: Bool = false) throws {
        try check(sqlite3_open(databaseURL.path, &connection))
        if walMode {
            try execute("PRAGMA journal_mode=WAL")
        }
        try execute("CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
    }

    func insertText(_ value: String, key: String = "cursorAuth/accessToken") throws {
        try insert(key: key) { statement in
            sqlite3_bind_text(statement, 2, value, -1, Self.transient)
        }
    }

    func insertBlob(_ value: Data, key: String = "cursorAuth/accessToken") throws {
        try insert(key: key) { statement in
            value.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), Self.transient)
            }
        }
    }

    func close() {
        sqlite3_close(connection)
        connection = nil
    }

    // Apple's system SQLite can keep WAL sidecars after the last close, so checkpoint and remove them
    // to reproduce an idle WAL database whose writer has quit cleanly.
    func closeAndRemoveWALSidecars() throws {
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
        close()
        for suffix in ["-wal", "-shm"] {
            let path = databaseURL.path + suffix
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        }
    }

    func directoryListing() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directoryURL.path).sorted()
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func insert(key: String, bindValue: (OpaquePointer) -> Int32) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_prepare_v2(connection, "INSERT INTO ItemTable (key, value) VALUES (?, ?)", -1, &statement, nil))
        guard let statement else { throw HarnessError.sqlite(SQLITE_ERROR) }
        try check(sqlite3_bind_text(statement, 1, key, -1, Self.transient))
        try check(bindValue(statement))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw HarnessError.sqlite(SQLITE_ERROR) }
    }

    private func execute(_ sql: String) throws {
        try check(sqlite3_exec(connection, sql, nil, nil, nil))
    }

    private func check(_ code: Int32) throws {
        guard code == SQLITE_OK else { throw HarnessError.sqlite(code) }
    }

    enum HarnessError: Error {
        case sqlite(Int32)
    }
}
