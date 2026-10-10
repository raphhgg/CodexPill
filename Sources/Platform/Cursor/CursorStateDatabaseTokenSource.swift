import Foundation
import SQLite3

enum CursorStateDatabaseError: Error, Equatable {
    case sqlite(code: Int32)
}

struct CursorStateDatabaseTokenSource: CursorAccessTokenSource {
    static let accessTokenKey = "cursorAuth/accessToken"

    let databaseURL: URL

    init(
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    ) {
        self.databaseURL = databaseURL
    }

    func lookup() throws -> CursorAccessTokenLookup {
        let fileManager = FileManager.default
        let path = databaseURL.path
        guard fileManager.fileExists(atPath: path) else {
            return .cursorNotInstalled
        }

        guard
            let value = try readAccessTokenValue(
                hasWALSidecars: fileManager.fileExists(atPath: path + "-wal")
                    || fileManager.fileExists(atPath: path + "-shm")
            ),
            let token = CursorAccessToken(jwt: value)
        else {
            return .signedOut
        }

        return .token(token)
    }

    static func decodeTokenValue(_ data: Data) -> String? {
        if looksLikeASCIIInUTF16LE(data) {
            return String(data: data, encoding: .utf16LittleEndian)
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        return String(data: data, encoding: .utf16LittleEndian)
    }

    private func readAccessTokenValue(hasWALSidecars: Bool) throws -> String? {
        var database: OpaquePointer?
        defer { sqlite3_close(database) }

        // A read-only open of an idle WAL database may still need to create `-shm`.
        // `immutable=1` never touches the directory, so use it whenever Cursor is not running.
        let openCode: Int32
        if hasWALSidecars {
            openCode = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        } else {
            let uri = databaseURL.standardizedFileURL.absoluteString + "?immutable=1"
            openCode = sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        }
        guard openCode == SQLITE_OK, let database else {
            throw CursorStateDatabaseError.sqlite(code: openCode)
        }
        sqlite3_busy_timeout(database, 250)

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        let prepareCode = sqlite3_prepare_v2(
            database,
            "SELECT value FROM ItemTable WHERE key = ? LIMIT 1",
            -1,
            &statement,
            nil
        )
        guard prepareCode == SQLITE_OK, let statement else {
            throw CursorStateDatabaseError.sqlite(code: prepareCode)
        }

        let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bindCode = sqlite3_bind_text(statement, 1, Self.accessTokenKey, -1, sqliteTransient)
        guard bindCode == SQLITE_OK else {
            throw CursorStateDatabaseError.sqlite(code: bindCode)
        }

        let stepCode = sqlite3_step(statement)
        switch stepCode {
        case SQLITE_ROW:
            return Self.columnValue(statement)
        case SQLITE_DONE:
            return nil
        default:
            throw CursorStateDatabaseError.sqlite(code: stepCode)
        }
    }

    private static func columnValue(_ statement: OpaquePointer) -> String? {
        switch sqlite3_column_type(statement, 0) {
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, 0) else { return nil }
            let count = Int(sqlite3_column_bytes(statement, 0))
            return String(decoding: UnsafeBufferPointer(start: text, count: count), as: UTF8.self)
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            return decodeTokenValue(Data(bytes: bytes, count: count))
        default:
            return nil
        }
    }

    private static func looksLikeASCIIInUTF16LE(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count.isMultiple(of: 2) else { return false }

        let bytes = Array(data)
        return stride(from: 0, to: bytes.count, by: 2).allSatisfy { index in
            (1...127).contains(bytes[index]) && bytes[index + 1] == 0
        }
    }
}
