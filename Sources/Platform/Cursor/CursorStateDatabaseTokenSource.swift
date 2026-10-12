import Foundation

struct CursorStateDatabaseTokenSource: CursorAccessTokenSource {
    static let accessTokenKey = "cursorAuth/accessToken"
    static let emailKey = "cursorAuth/cachedEmail"

    let databaseURL: URL

    init(databaseURL: URL = CursorStateDatabase.defaultURL) {
        self.databaseURL = databaseURL
    }

    func lookup() throws -> CursorAccessTokenLookup {
        let database = CursorStateDatabase(url: databaseURL)
        guard database.exists else {
            return .cursorNotInstalled
        }

        let values = try database.values(forKeys: [Self.accessTokenKey, Self.emailKey])
        guard let value = values[Self.accessTokenKey], let token = Self.accessToken(from: value) else {
            return .signedOut
        }

        return .token(token, email: values[Self.emailKey].flatMap(Self.email(from:)))
    }

    static func accessToken(from value: CursorStateValue) -> CursorAccessToken? {
        text(value).flatMap(CursorAccessToken.init(jwt:))
    }

    /// Cursor stores the email JSON-encoded, with quotes.
    private static func email(from value: CursorStateValue) -> String? {
        let email = text(value)?.trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespacesAndNewlines))
        return email?.isEmpty == false ? email : nil
    }

    private static func text(_ value: CursorStateValue) -> String? {
        switch value {
        case .text(let text): text
        case .blob(let data): decodeTokenValue(data)
        }
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
