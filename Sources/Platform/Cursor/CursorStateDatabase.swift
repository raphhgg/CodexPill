import Foundation
import SQLite3

enum CursorStateDatabaseError: Error, Equatable {
    case sqlite(code: Int32)
    /// Another process still has the database open, so CodexPill did not write.
    case busy
}

/// One `ItemTable` value, kept in the storage class Cursor used so a write puts back exactly what was read.
enum CursorStateValue: Sendable, Equatable, Codable {
    case text(String)
    case blob(Data)
}

/// Keyed access to Cursor's `state.vscdb`. It never scans the database: every statement names its keys.
struct CursorStateDatabase: Sendable {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")

    /// The fixture database an isolated run (`CODEXPILL_ISOLATED_APP_SUPPORT_DIR`) uses instead of Cursor's.
    static func isolatedURL(root: URL) -> URL {
        root.appendingPathComponent("Cursor/state.vscdb")
    }

    let url: URL
    /// How long a write waits for Cursor's own connections to close before giving up.
    var writeBusyTimeout: Duration = .seconds(5)

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Reads the given keys read-only. Keys with no row are left out.
    func values(forKeys keys: [String]) throws -> [String: CursorStateValue] {
        let connection = try Connection(openingReadOnly: url)
        return try connection.values(forKeys: keys)
    }

    /// Replaces the given keys in one transaction: keys in `values` are written, keys in `removing` are deleted.
    /// Run this only after Cursor has quit. It folds Cursor's WAL into the main file first and refuses to
    /// write while another connection still holds the database.
    func write(_ values: [String: CursorStateValue], removing removedKeys: [String]) throws {
        let connection = try Connection(openingReadWrite: url, busyTimeout: writeBusyTimeout)
        try connection.checkpointWAL()
        try connection.transaction {
            for key in values.keys.sorted() {
                try connection.replace(key: key, with: values[key]!)
            }
            for key in removedKeys where values[key] == nil {
                try connection.delete(key: key)
            }
        }
        try connection.checkpointWAL()
    }

    /// Reads the given keys through a read-write connection, for the moment between quitting Cursor and writing.
    func valuesForWrite(forKeys keys: [String]) throws -> [String: CursorStateValue] {
        let connection = try Connection(openingReadWrite: url, busyTimeout: writeBusyTimeout)
        try connection.checkpointWAL()
        return try connection.values(forKeys: keys)
    }
}

private final class Connection {
    private let handle: OpaquePointer

    init(openingReadOnly url: URL) throws {
        let path = url.path
        let hasSidecars = ["-wal", "-shm", "-journal"].contains { FileManager.default.fileExists(atPath: path + $0) }

        // A read-only open of an idle WAL database may still need to create `-shm`, so an idle database is opened
        // with `immutable=1`, which never touches the directory. A sidecar means a writer is open or crashed, and
        // `immutable=1` would read its uncommitted pages, so then SQLite reads normally, or refuses a hot journal.
        var database: OpaquePointer?
        let code: Int32
        if hasSidecars {
            code = sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil)
        } else {
            let uri = url.standardizedFileURL.absoluteString + "?immutable=1"
            code = sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        }
        handle = try Self.opened(database, code: code)
        sqlite3_busy_timeout(handle, 250)
    }

    init(openingReadWrite url: URL, busyTimeout: Duration) throws {
        var database: OpaquePointer?
        // Never create the file: a missing database means Cursor is not installed.
        let code = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil)
        handle = try Self.opened(database, code: code)
        sqlite3_busy_timeout(handle, Int32(busyTimeout / .milliseconds(1)))
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    func values(forKeys keys: [String]) throws -> [String: CursorStateValue] {
        var values: [String: CursorStateValue] = [:]
        for key in keys {
            try withStatement("SELECT value FROM ItemTable WHERE key = ? LIMIT 1") { statement in
                try check(sqlite3_bind_text(statement, 1, key, -1, Self.transient))
                let code = sqlite3_step(statement)
                switch code {
                case SQLITE_ROW:
                    values[key] = Self.columnValue(statement)
                case SQLITE_DONE:
                    break
                default:
                    throw Self.error(for: code)
                }
            }
        }
        return values
    }

    func replace(key: String, with value: CursorStateValue) throws {
        try withStatement("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)") { statement in
            try check(sqlite3_bind_text(statement, 1, key, -1, Self.transient))
            switch value {
            case .text(let text):
                try check(sqlite3_bind_text(statement, 2, text, -1, Self.transient))
            case .blob(let data):
                try check(data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), Self.transient)
                })
            }
            try stepDone(statement)
        }
    }

    func delete(key: String) throws {
        try withStatement("DELETE FROM ItemTable WHERE key = ?") { statement in
            try check(sqlite3_bind_text(statement, 1, key, -1, Self.transient))
            try stepDone(statement)
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        // IMMEDIATE takes the write lock up front, so a busy database fails before any row changes.
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            sqlite3_exec(handle, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    /// Folds the WAL into the main file and truncates it. SQLite reports `busy` when another connection
    /// still reads or writes, which means Cursor, or a Cursor helper, has not let go of the database yet.
    func checkpointWAL() throws {
        try withStatement("PRAGMA wal_checkpoint(TRUNCATE)") { statement in
            let code = sqlite3_step(statement)
            guard code == SQLITE_ROW else { throw Self.error(for: code) }
            // A rollback-journal database reports -1 frames and is never busy.
            if sqlite3_column_int(statement, 0) != 0 {
                throw CursorStateDatabaseError.busy
            }
        }
    }

    private func execute(_ sql: String) throws {
        try check(sqlite3_exec(handle, sql, nil, nil, nil))
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_prepare_v2(handle, sql, -1, &statement, nil))
        guard let statement else { throw CursorStateDatabaseError.sqlite(code: SQLITE_ERROR) }
        try body(statement)
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE else { throw Self.error(for: code) }
    }

    private func check(_ code: Int32) throws {
        guard code == SQLITE_OK else { throw Self.error(for: code) }
    }

    private static func error(for code: Int32) -> CursorStateDatabaseError {
        switch code & 0xFF {
        case SQLITE_BUSY, SQLITE_LOCKED: .busy
        default: .sqlite(code: code)
        }
    }

    private static func opened(_ database: OpaquePointer?, code: Int32) throws -> OpaquePointer {
        guard code == SQLITE_OK, let database else {
            sqlite3_close_v2(database)
            throw error(for: code)
        }
        return database
    }

    private static func columnValue(_ statement: OpaquePointer) -> CursorStateValue? {
        switch sqlite3_column_type(statement, 0) {
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, 0) else { return nil }
            let count = Int(sqlite3_column_bytes(statement, 0))
            return .text(String(decoding: UnsafeBufferPointer(start: text, count: count), as: UTF8.self))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { return .blob(Data()) }
            return .blob(Data(bytes: bytes, count: count))
        default:
            return nil
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
