import Foundation

struct CursorStateDatabaseTokenSource: CursorAccessTokenSource {
    static let accessTokenKey = CursorSignIn.accessTokenKey

    let databaseURL: URL

    init(databaseURL: URL = CursorStateDatabase.defaultURL) {
        self.databaseURL = databaseURL
    }

    func lookup() throws -> CursorAccessTokenLookup {
        let database = CursorStateDatabase(url: databaseURL)
        guard database.exists else {
            return .cursorNotInstalled
        }

        guard
            let value = try database.values(forKeys: [Self.accessTokenKey])[Self.accessTokenKey],
            let token = CursorSignIn.accessToken(from: value)
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

    private static func looksLikeASCIIInUTF16LE(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count.isMultiple(of: 2) else { return false }

        let bytes = Array(data)
        return stride(from: 0, to: bytes.count, by: 2).allSatisfy { index in
            (1...127).contains(bytes[index]) && bytes[index + 1] == 0
        }
    }
}
