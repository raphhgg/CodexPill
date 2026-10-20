import CryptoKit
import Foundation

/// A PKCE pair (RFC 7636, S256). The verifier stays in memory for one sign-in and is sent only to the token endpoint.
struct ClaudePKCE: RedactedClaudeSecret {
    let verifier: String
    let challenge: String

    init(verifier: String) {
        self.verifier = verifier
        challenge = ClaudeOAuth.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func random() -> ClaudePKCE {
        ClaudePKCE(verifier: ClaudeOAuth.randomURLSafeString())
    }
}

/// What the browser sent to the loopback redirect.
enum ClaudeOAuthCallback: Equatable, Sendable {
    case authorized(code: String, state: String)
    case denied(error: String, state: String?)
}

enum ClaudeSignInError: Error, Equatable {
    case stateMismatch
    case denied
    case timedOut
    case listenerFailed
    case token(ClaudeTokenError)
}

enum ClaudeTokenError: Error, Equatable {
    /// The refresh token or authorization code is no longer valid. Only a new sign-in helps.
    case invalidGrant
    case rejected(status: Int)
    case transport
    case malformedResponse
}

/// Claude's OAuth contract as Claude Code uses it: the same public client, authorize page, and token endpoint.
/// Refill asks only for `user:profile`, the scope `api/oauth/usage` needs.
enum ClaudeOAuth {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = URL(string: "https://claude.com/cai/oauth/authorize")!
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let revokeURL = URL(string: "https://platform.claude.com/v1/oauth/token/revoke")!
    static let scope = "user:profile"
    static let callbackPath = "/callback"

    static func redirectURI(port: UInt16) -> URL {
        URL(string: "http://localhost:\(port)\(callbackPath)")!
    }

    static func authorizeURL(redirectURI: URL, state: String, pkce: ClaudePKCE) -> URL {
        let parameters = [
            ("code", "true"),
            ("client_id", clientID),
            ("response_type", "code"),
            ("redirect_uri", redirectURI.absoluteString),
            ("scope", scope),
            ("code_challenge", pkce.challenge),
            ("code_challenge_method", "S256"),
            ("state", state),
        ]
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = parameters.map { "\($0)=\(formEncoded($1))" }.joined(separator: "&")
        return components.url!
    }

    /// Reads the request line the browser sent, such as `GET /callback?code=…&state=… HTTP/1.1`.
    /// Returns nil for anything else, such as `/favicon.ico`.
    static func callback(fromRequestLine requestLine: String) -> ClaudeOAuthCallback? {
        let parts = requestLine.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[2].hasPrefix("HTTP/"),
              let components = URLComponents(string: "http://localhost\(parts[1])"),
              components.path == callbackPath
        else {
            return nil
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        if let error = value("error") {
            return .denied(error: error, state: value("state"))
        }
        guard let code = value("code"), let state = value("state") else {
            return .denied(error: "missing_code", state: value("state"))
        }
        return .authorized(code: code, state: state)
    }

    /// The authorization code, only when the callback carries the `state` this sign-in sent.
    static func authorizationCode(from callback: ClaudeOAuthCallback, expectedState: String) throws(ClaudeSignInError) -> String {
        switch callback {
        case let .authorized(code, state):
            guard state == expectedState else { throw .stateMismatch }
            return code
        case let .denied(_, state):
            guard state == expectedState else { throw .stateMismatch }
            throw .denied
        }
    }

    static func exchangeRequest(code: String, pkce: ClaudePKCE, state: String, redirectURI: URL) -> URLRequest {
        tokenRequest(url: tokenURL, body: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI.absoluteString,
            "client_id": clientID,
            "code_verifier": pkce.verifier,
            "state": state,
        ])
    }

    static func refreshRequest(_ refreshToken: ClaudeRefreshToken) -> URLRequest {
        tokenRequest(url: tokenURL, body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken.exposedValue,
            "client_id": clientID,
            "scope": scope,
        ])
    }

    static func revokeRequest(_ refreshToken: ClaudeRefreshToken) -> URLRequest {
        tokenRequest(url: revokeURL, body: [
            "token": refreshToken.exposedValue,
            "token_type_hint": "refresh_token",
            "client_id": clientID,
        ])
    }

    /// Parses a token endpoint answer. When `current` is the sign-in being refreshed, a reply without `refresh_token`
    /// keeps its refresh token, a reply without an account keeps its email, and the plan always stays.
    static func signIn(
        fromTokenResponse data: Data,
        status: Int,
        receivedAt: Date,
        refreshing current: ClaudeSignIn? = nil
    ) throws(ClaudeTokenError) -> ClaudeSignIn {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard status == 200 else {
            let error = try? decoder.decode(TokenErrorDTO.self, from: data)
            if (status == 400 || status == 401), error?.error == "invalid_grant" {
                throw .invalidGrant
            }
            throw .rejected(status: status)
        }
        guard
            let response = try? decoder.decode(TokenResponseDTO.self, from: data),
            let accessToken = ClaudeAccessToken(response.accessToken),
            let refreshToken = response.refreshToken.flatMap(ClaudeRefreshToken.init) ?? current?.refreshToken,
            response.expiresIn > 0
        else {
            throw .malformedResponse
        }
        return ClaudeSignIn(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: receivedAt.addingTimeInterval(response.expiresIn),
            email: response.account?.emailAddress.flatMap { $0.isEmpty ? nil : $0 } ?? current?.email,
            planName: current?.planName
        )
    }

    static func randomURLSafeString() -> String {
        var generator = SystemRandomNumberGenerator()
        return base64URL(Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreservedCharacters) ?? value
    }

    private static let unreservedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func tokenRequest(url: URL, body: [String: String]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }
}

private struct TokenResponseDTO: Decodable {
    struct Account: Decodable {
        let emailAddress: String?
    }

    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval
    let account: Account?
}

private struct TokenErrorDTO: Decodable {
    let error: String?
}
