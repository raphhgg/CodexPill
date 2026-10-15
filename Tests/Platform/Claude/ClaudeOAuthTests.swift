import Foundation
import Testing

@testable import Refill

struct ClaudeOAuthTests {
    private let now = Date(timeIntervalSince1970: 1_791_633_600)

    @Test
    func pkceMatchesTheRFC7636Example() {
        let pkce = ClaudePKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(String(describing: pkce) == "ClaudePKCE(redacted)")
    }

    @Test
    func theAuthorizeURLUsesClaudeCodesPublicClientWithALoopbackRedirect() {
        let url = ClaudeOAuth.authorizeURL(
            redirectURI: ClaudeOAuth.redirectURI(port: 54_545),
            state: "fixed-state-123",
            pkce: ClaudePKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        )

        #expect(url.absoluteString == "https://claude.com/cai/oauth/authorize?code=true"
            + "&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code"
            + "&redirect_uri=http%3A%2F%2Flocalhost%3A54545%2Fcallback&scope=user%3Aprofile"
            + "&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256"
            + "&state=fixed-state-123")
    }

    @Test
    func readsTheCallbackRequestLineAndIgnoresOtherPaths() {
        #expect(ClaudeOAuth.callback(fromRequestLine: "GET /callback?code=fake-code&state=fixed-state-123 HTTP/1.1")
            == .authorized(code: "fake-code", state: "fixed-state-123"))
        #expect(ClaudeOAuth.callback(fromRequestLine: "GET /callback?error=access_denied&state=fixed-state-123 HTTP/1.1")
            == .denied(error: "access_denied", state: "fixed-state-123"))
        #expect(ClaudeOAuth.callback(fromRequestLine: "GET /callback?state=fixed-state-123 HTTP/1.1")
            == .denied(error: "missing_code", state: "fixed-state-123"))
        #expect(ClaudeOAuth.callback(fromRequestLine: "GET /favicon.ico HTTP/1.1") == nil)
        #expect(ClaudeOAuth.callback(fromRequestLine: "POST /callback?code=fake-code&state=fixed-state-123 HTTP/1.1") == nil)
        #expect(ClaudeOAuth.callback(fromRequestLine: "garbage") == nil)
    }

    @Test
    func aCallbackForAnotherStateIsRejected() throws {
        #expect(throws: ClaudeSignInError.stateMismatch) {
            try ClaudeOAuth.authorizationCode(from: .authorized(code: "fake-code", state: "other-state"), expectedState: "fixed-state-123")
        }
        #expect(throws: ClaudeSignInError.stateMismatch) {
            try ClaudeOAuth.authorizationCode(from: .denied(error: "access_denied", state: nil), expectedState: "fixed-state-123")
        }
        #expect(throws: ClaudeSignInError.denied) {
            try ClaudeOAuth.authorizationCode(from: .denied(error: "access_denied", state: "fixed-state-123"), expectedState: "fixed-state-123")
        }
        #expect(try ClaudeOAuth.authorizationCode(
            from: .authorized(code: "fake-code", state: "fixed-state-123"),
            expectedState: "fixed-state-123"
        ) == "fake-code")
    }

    @Test
    func parsesTokenResponsesAndARefreshKeepsWhatItsReplyLeavesOut() throws {
        let exchanged = try ClaudeOAuth.signIn(
            fromTokenResponse: Data(#"{"token_type":"Bearer","access_token":"fake-access","refresh_token":"fake-refresh","expires_in":28800,"scope":"user:profile","account":{"uuid":"fake-uuid","email_address":"sam@example.com"}}"#.utf8),
            status: 200,
            receivedAt: now
        )
        #expect(exchanged == .fake(access: "fake-access", refresh: "fake-refresh", expiresAt: Date(timeIntervalSince1970: 1_791_662_400), email: "sam@example.com"))

        let current = ClaudeSignIn.fake(access: "fake-access", refresh: "fake-refresh", expiresAt: now, email: "sam@example.com", planName: "max_20x")
        let refreshed = try ClaudeOAuth.signIn(
            fromTokenResponse: Data(#"{"access_token":"fake-access-2","expires_in":3600}"#.utf8),
            status: 200,
            receivedAt: now,
            refreshing: current
        )
        #expect(refreshed == .fake(access: "fake-access-2", refresh: "fake-refresh", expiresAt: Date(timeIntervalSince1970: 1_791_637_200), email: "sam@example.com", planName: "max_20x"))

        #expect(throws: ClaudeTokenError.malformedResponse) {
            try ClaudeOAuth.signIn(fromTokenResponse: Data(#"{"access_token":"fake-access","expires_in":3600}"#.utf8), status: 200, receivedAt: now)
        }
    }

    @Test
    func invalidGrantMeansSignInAgainAndOtherFailuresDoNot() {
        #expect(throws: ClaudeTokenError.invalidGrant) {
            try ClaudeOAuth.signIn(fromTokenResponse: Data(#"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#.utf8), status: 400, receivedAt: now)
        }
        #expect(throws: ClaudeTokenError.rejected(status: 400)) {
            try ClaudeOAuth.signIn(fromTokenResponse: Data(#"{"error":"invalid_request"}"#.utf8), status: 400, receivedAt: now)
        }
        #expect(throws: ClaudeTokenError.rejected(status: 503)) {
            try ClaudeOAuth.signIn(fromTokenResponse: Data("<html>".utf8), status: 503, receivedAt: now)
        }
    }

    @Test
    func tokenRequestsSendJSONToClaudesTokenEndpoint() throws {
        let refresh = ClaudeOAuth.refreshRequest(try #require(ClaudeRefreshToken("fake-refresh")))
        #expect(refresh.url?.absoluteString == "https://platform.claude.com/v1/oauth/token")
        #expect(refresh.httpMethod == "POST")
        #expect(refresh.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(String(decoding: refresh.httpBody ?? Data(), as: UTF8.self)
            == #"{"client_id":"9d1c250a-e61b-44d9-88ed-5944d1962f5e","grant_type":"refresh_token","refresh_token":"fake-refresh","scope":"user:profile"}"#)

        let exchange = ClaudeOAuth.exchangeRequest(
            code: "fake-code",
            pkce: ClaudePKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            state: "fixed-state-123",
            redirectURI: ClaudeOAuth.redirectURI(port: 54_545)
        )
        #expect(String(decoding: exchange.httpBody ?? Data(), as: UTF8.self)
            == #"{"client_id":"9d1c250a-e61b-44d9-88ed-5944d1962f5e","code":"fake-code","code_verifier":"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk","grant_type":"authorization_code","redirect_uri":"http:\/\/localhost:54545\/callback","state":"fixed-state-123"}"#)

        let revoke = ClaudeOAuth.revokeRequest(try #require(ClaudeRefreshToken("fake-refresh")))
        #expect(revoke.url?.absoluteString == "https://platform.claude.com/v1/oauth/token/revoke")
    }

    @Test
    func theSignInIsRefreshedFiveMinutesBeforeItExpires() {
        let signIn = ClaudeSignIn.fake(access: "fake-access", refresh: "fake-refresh", expiresAt: now)

        #expect(signIn.needsRefresh(at: now.addingTimeInterval(-301)) == false)
        #expect(signIn.needsRefresh(at: now.addingTimeInterval(-300)) == true)
        #expect(signIn.isExpired(at: now.addingTimeInterval(-1)) == false)
        #expect(signIn.isExpired(at: now) == true)
    }

    @Test
    func noTokenAppearsWhenTheSignInOrItsRequestsArePrinted() throws {
        let signIn = ClaudeSignIn.fake(access: "fake-own-access", refresh: "fake-own-refresh", expiresAt: now)
        var dumped = ""
        dump(signIn, to: &dumped)

        let printed = [
            String(describing: signIn),
            String(reflecting: signIn),
            String(describing: signIn.refreshToken),
            String(reflecting: signIn.refreshToken),
            dumped,
            String(describing: ClaudeOAuth.refreshRequest(signIn.refreshToken)),
            String(reflecting: ClaudeOAuth.revokeRequest(signIn.refreshToken)),
            String(describing: Mirror(reflecting: signIn).children.map(\.value)),
        ]
        #expect(printed.filter { $0.contains("fake-own-access") || $0.contains("fake-own-refresh") } == [])
        #expect(String(describing: signIn.refreshToken) == "ClaudeRefreshToken(redacted)")
    }
}

struct ClaudeBrowserSignInTests {
    @Test
    func opensTheAuthorizeURLAndExchangesTheCodeFromTheMatchingCallback() async throws {
        let receiver = StubRedirectReceiver(callback: .authorized(code: "fake-code", state: "fixed-state-123"))
        let endpoint = RecordingTokenEndpoint()
        let opened = LockedValue<[URL]>([])

        let signIn = try await makeFlow(receiver: receiver, endpoint: endpoint, opened: opened).signIn()

        #expect(opened.value.map(\.absoluteString) == [
            "https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"
                + "&response_type=code&redirect_uri=http%3A%2F%2Flocalhost%3A54545%2Fcallback&scope=user%3Aprofile"
                + "&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256&state=fixed-state-123",
        ])
        #expect(endpoint.exchanges.value == ["fake-code dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk fixed-state-123 http://localhost:54545/callback"])
        #expect(signIn == .fake(access: "fake-access", refresh: "fake-refresh", expiresAt: Date(timeIntervalSince1970: 1_791_633_600)))
        #expect(receiver.stopped.value == true)
    }

    @Test
    func aCallbackWithAnotherStateIsNeverExchanged() async {
        let receiver = StubRedirectReceiver(callback: .authorized(code: "fake-code", state: "forged-state"))
        let endpoint = RecordingTokenEndpoint()

        await #expect(throws: ClaudeSignInError.stateMismatch) {
            try await makeFlow(receiver: receiver, endpoint: endpoint, opened: LockedValue([])).signIn()
        }
        #expect(endpoint.exchanges.value == [])
        #expect(receiver.stopped.value == true)
    }

    @Test
    func aSignInThatNeverComesBackTimesOut() async {
        var flow = makeFlow(receiver: StubRedirectReceiver(callback: nil), endpoint: RecordingTokenEndpoint(), opened: LockedValue([]))
        flow.timeout = .milliseconds(20)

        await #expect(throws: ClaudeSignInError.timedOut) {
            try await flow.signIn()
        }
    }

    @Test
    func theLoopbackListenerAnswersTheBrowserAndReturnsTheCallback() async throws {
        let receiver = try await LoopbackClaudeOAuthReceiver.start()
        defer { receiver.stop() }
        let port = try #require(receiver.redirectURI.port)
        #expect(receiver.redirectURI.absoluteString == "http://localhost:\(port)/callback")

        let session = URLSession(configuration: .ephemeral)
        let (_, favicon) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/favicon.ico")!)
        #expect((favicon as? HTTPURLResponse)?.statusCode == 404)

        let (page, callback) = try await session.data(from: URL(string: "http://[::1]:\(port)/callback?code=fake-code&state=fixed-state-123")!)
        #expect((callback as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: page, as: UTF8.self).contains("Signed in to Claude"))
        #expect(try await receiver.nextCallback() == .authorized(code: "fake-code", state: "fixed-state-123"))
    }

    private func makeFlow(receiver: StubRedirectReceiver, endpoint: RecordingTokenEndpoint, opened: LockedValue<[URL]>) -> ClaudeBrowserSignIn {
        ClaudeBrowserSignIn(
            tokenEndpoint: endpoint,
            startReceiver: { receiver },
            openURL: { url in opened.update { $0.append(url) } },
            makePKCE: { ClaudePKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") },
            makeState: { "fixed-state-123" },
            now: { Date(timeIntervalSince1970: 1_791_633_600) }
        )
    }
}

final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) {
        stored = value
    }

    var value: Value {
        lock.withLock { stored }
    }

    func update(_ change: (inout Value) -> Void) {
        lock.withLock { change(&stored) }
    }
}

private struct StubRedirectReceiver: ClaudeOAuthRedirectReceiver {
    let callback: ClaudeOAuthCallback?
    let stopped = LockedValue(false)
    let redirectURI = ClaudeOAuth.redirectURI(port: 54_545)

    func nextCallback() async throws -> ClaudeOAuthCallback {
        guard let callback else {
            try await Task.sleep(for: .seconds(60))
            throw CancellationError()
        }
        return callback
    }

    func stop() {
        stopped.update { $0 = true }
    }
}

private struct RecordingTokenEndpoint: ClaudeTokenEndpoint {
    let exchanges = LockedValue<[String]>([])

    func exchange(code: String, pkce: ClaudePKCE, state: String, redirectURI: URL, now: Date) async throws(ClaudeTokenError) -> ClaudeSignIn {
        exchanges.update { $0.append("\(code) \(pkce.verifier) \(state) \(redirectURI.absoluteString)") }
        return .fake(access: "fake-access", refresh: "fake-refresh", expiresAt: now)
    }

    func refresh(_: ClaudeSignIn, now _: Date) async throws(ClaudeTokenError) -> ClaudeSignIn {
        throw .transport
    }

    func revoke(_: ClaudeRefreshToken) async {}
}
