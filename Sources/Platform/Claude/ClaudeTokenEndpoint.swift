import Foundation

/// Claude's OAuth token endpoint: code exchange, refresh, and revoke for rusage's own sign-in.
protocol ClaudeTokenEndpoint: Sendable {
    func exchange(code: String, pkce: ClaudePKCE, state: String, redirectURI: URL, now: Date) async throws(ClaudeTokenError) -> ClaudeSignIn
    /// Sends `current`'s refresh token once. The new sign-in keeps what the reply leaves out, such as the plan.
    func refresh(_ current: ClaudeSignIn, now: Date) async throws(ClaudeTokenError) -> ClaudeSignIn
    /// Best effort. Signing out never waits on or fails because of it.
    func revoke(_ refreshToken: ClaudeRefreshToken) async
}

final class URLSessionClaudeTokenEndpoint: ClaudeTokenEndpoint {
    private let session = ClaudeUsageAPI.makeSession()

    deinit {
        session.finishTasksAndInvalidate()
    }

    func exchange(code: String, pkce: ClaudePKCE, state: String, redirectURI: URL, now: Date) async throws(ClaudeTokenError) -> ClaudeSignIn {
        let (data, status) = try await send(ClaudeOAuth.exchangeRequest(code: code, pkce: pkce, state: state, redirectURI: redirectURI))
        return try ClaudeOAuth.signIn(fromTokenResponse: data, status: status, receivedAt: now)
    }

    func refresh(_ current: ClaudeSignIn, now: Date) async throws(ClaudeTokenError) -> ClaudeSignIn {
        let (data, status) = try await send(ClaudeOAuth.refreshRequest(current.refreshToken))
        return try ClaudeOAuth.signIn(fromTokenResponse: data, status: status, receivedAt: now, refreshing: current)
    }

    func revoke(_ refreshToken: ClaudeRefreshToken) async {
        _ = try? await send(ClaudeOAuth.revokeRequest(refreshToken))
    }

    private func send(_ request: URLRequest) async throws(ClaudeTokenError) -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw ClaudeTokenError.transport }
            return (data, httpResponse.statusCode)
        } catch {
            throw .transport
        }
    }
}
