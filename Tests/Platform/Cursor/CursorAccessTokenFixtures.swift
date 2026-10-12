import Foundation

@testable import Refill

enum CursorAccessTokenFixtures {
    static let referenceDate = Date(timeIntervalSince1970: 1_791_000_000)

    static func jwt(claims: [String: Any]) -> String {
        let header = base64URL(Data(#"{"alg":"none","typ":"JWT"}"#.utf8))
        let payload = base64URL(try! JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys]))
        return "\(header).\(payload).signature"
    }

    static func jwt(subject: String = "auth0|user_abc", expiresAt: Date) -> String {
        jwt(claims: ["sub": subject, "exp": Int(expiresAt.timeIntervalSince1970)])
    }

    static func token(subject: String = "auth0|user_abc", expiresAt: Date) -> CursorAccessToken {
        CursorAccessToken(jwt: jwt(subject: subject, expiresAt: expiresAt))!
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
