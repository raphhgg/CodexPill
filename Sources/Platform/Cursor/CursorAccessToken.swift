import Foundation

struct CursorAccessToken: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let jwt: String
    let userID: String
    let expiresAt: Date

    init?(jwt rawValue: String) {
        let jwt = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard
            parts.count >= 2,
            let payloadData = Self.base64URLDecoded(String(parts[1])),
            let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
            let subject = payload["sub"] as? String,
            let userID = subject.split(separator: "|", omittingEmptySubsequences: false).last.map(String.init),
            Self.isValidUserID(userID),
            let expiration = payload["exp"] as? NSNumber
        else {
            return nil
        }

        self.jwt = jwt
        self.userID = userID
        self.expiresAt = Date(timeIntervalSince1970: expiration.doubleValue)
    }

    func isUsable(at now: Date) -> Bool {
        expiresAt.timeIntervalSince(now) > 60
    }

    var cookieHeaderValue: String {
        "WorkosCursorSessionToken=\(userID)%3A%3A\(jwt)"
    }

    var description: String {
        "CursorAccessToken(redacted)"
    }

    var debugDescription: String {
        description
    }

    var customMirror: Mirror {
        Mirror(self, children: EmptyCollection<Mirror.Child>())
    }

    private static func base64URLDecoded(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    // The user ID is spliced into a cookie value, so only allow characters that need no escaping.
    private static func isValidUserID(_ userID: String) -> Bool {
        !userID.isEmpty && userID.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", ".", "_", "-":
                true
            default:
                false
            }
        }
    }
}
