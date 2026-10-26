import Foundation
import os
import Testing

@testable import RUsage

struct CursorOwnSignInTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func theBrowserSignInPollsUntilCursorAnswersThenKeepsTheTokensAndEmail() async throws {
        let store = FileCursorSignInStore(fileURL: temporaryFile())
        let access = CursorAccessTokenFixtures.jwt(expiresAt: now.addingTimeInterval(60 * 86_400))
        let web = CursorAuthWebProbe(polls: [(404, "{}"), (404, "{}"), (200, #"{"accessToken":"\#(access)","refreshToken":"r1"}"#)])
        web.getMeResponse = (200, #"{"email":"sam@example.com"}"#)
        let opened = OSAllocatedUnfairLock<[URL]>(initialState: [])
        let signIn = CursorOwnSignIn(store: store, web: web, openURL: { url in opened.withLock { $0.append(url) } }, sleep: { _ in }, now: { now })

        try await signIn.signIn()

        let url = try #require(opened.withLock { $0.first })
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(url.host == "cursor.com" && url.path == "/loginDeepControl")
        #expect(query.first { $0.name == "mode" }?.value == "login")
        #expect(web.pollCount == 3)
        #expect(store.read(allowingPrompt: false) == .found(CursorSignIn(accessToken: access, refreshToken: "r1", email: "sam@example.com")))
    }

    @Test
    func aSignInCursorNeverFinishesTimesOutWithoutSavingAnything() async {
        let store = FileCursorSignInStore(fileURL: temporaryFile())
        let web = CursorAuthWebProbe(polls: Array(repeating: (404, "{}"), count: 150))
        let signIn = CursorOwnSignIn(store: store, web: web, openURL: { _ in }, sleep: { _ in }, now: { now })

        await #expect(throws: CursorSignInError.timedOut) {
            try await signIn.signIn()
        }
        #expect(store.read(allowingPrompt: false) == .notFound)
    }

    @Test
    func aTokenCloseToExpiringIsRenewedAndOneCursorRefusesIsDropped() async {
        let store = FileCursorSignInStore(fileURL: temporaryFile())
        let old = CursorAccessTokenFixtures.jwt(expiresAt: now.addingTimeInterval(3_600))
        let new = CursorAccessTokenFixtures.jwt(expiresAt: now.addingTimeInterval(60 * 86_400))
        _ = store.save(CursorSignIn(accessToken: old, refreshToken: "r1", email: "sam@example.com"))
        let web = CursorAuthWebProbe(polls: [])
        web.refreshResponse = (200, #"{"access_token":"\#(new)"}"#)
        let signIn = CursorOwnSignIn(store: store, web: web, openURL: { _ in }, sleep: { _ in }, now: { now })

        await signIn.refreshIfNeeded()

        #expect(web.refreshedTokens == ["r1"])
        #expect(store.read(allowingPrompt: false) == .found(CursorSignIn(accessToken: new, refreshToken: new, email: "sam@example.com")))

        _ = store.save(CursorSignIn(accessToken: old, refreshToken: "r2"))
        web.refreshResponse = (200, #"{"shouldLogout":true}"#)
        await signIn.refreshIfNeeded()

        #expect(store.read(allowingPrompt: false) == .notFound)
    }

    @Test
    func readsUseRusagesOwnSignInOnlyWhileItIsOn() throws {
        let store = FileCursorSignInStore(fileURL: temporaryFile())
        let own = CursorAccessTokenFixtures.jwt(expiresAt: now.addingTimeInterval(86_400))
        _ = store.save(CursorSignIn(accessToken: own, refreshToken: "r1", email: "sam@example.com"))
        let usesOwn = OSAllocatedUnfairLock(initialState: true)
        let source = CursorSignInTokenSource(usesOwnSignIn: { usesOwn.withLock { $0 } }, store: store, cursorApp: CursorAppTokenStub())

        guard case let .token(_, email) = try source.lookup() else {
            Issue.record("Expected rusage's own sign-in")
            return
        }
        #expect(email == "sam@example.com")

        usesOwn.withLock { $0 = false }
        guard case .signedOut = try source.lookup() else {
            Issue.record("Expected the Cursor app's sign-in")
            return
        }
    }

    @Test
    func signingInTurnsOnRusagesOwnSignInAndSigningOutOrDisconnectingDropsIt() async throws {
        let fixture = CursorUsageFixture()
        defer { fixture.remove() }
        let store = FileCursorSignInStore(fileURL: temporaryFile())
        let access = CursorAccessTokenFixtures.jwt(expiresAt: now.addingTimeInterval(60 * 86_400))
        let web = CursorAuthWebProbe(polls: [(200, #"{"accessToken":"\#(access)","refreshToken":"r1"}"#), (200, #"{"accessToken":"\#(access)","refreshToken":"r1"}"#)])
        let usage = CursorUsage(
            settings: fixture.settings,
            client: CursorUsageClient(tokenSource: fixture, webClient: fixture),
            ownSignInClient: CursorOwnSignIn(store: store, web: web, openURL: { _ in }, sleep: { _ in }, now: { now })
        )
        #expect(usage.ownSignIn == .signedOut)

        try await usage.signIn()
        #expect(usage.ownSignIn == .signedIn)
        #expect(fixture.settings.value.isConnected)

        try await usage.signOut()
        #expect(usage.ownSignIn == .signedOut)
        #expect(fixture.settings.value.isConnected)
        #expect(store.read(allowingPrompt: false) == .notFound)

        try await usage.signIn()
        await usage.disconnect()
        #expect(!fixture.settings.value.isConnected && !fixture.settings.value.usesOwnSignIn)
        #expect(store.read(allowingPrompt: false) == .notFound)
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CursorOwnSignInTests-\(UUID().uuidString).json")
    }
}

private struct CursorAppTokenStub: CursorAccessTokenSource {
    func lookup() throws -> CursorAccessTokenLookup { .signedOut }
}

private final class CursorAuthWebProbe: CursorAuthWebClient, @unchecked Sendable {
    private let lock = NSLock()
    private var polls: [(Int, String)]
    private(set) var pollCount = 0
    private(set) var refreshedTokens: [String] = []
    var refreshResponse: (Int, String) = (500, "{}")
    var getMeResponse: (Int, String) = (500, "{}")

    init(polls: [(Int, String)]) {
        self.polls = polls
    }

    func poll(_: URL) async throws -> (status: Int, data: Data) {
        lock.withLock {
            pollCount += 1
            let (status, body) = polls.isEmpty ? (404, "{}") : polls.removeFirst()
            return (status, Data(body.utf8))
        }
    }

    func refresh(refreshToken: String) async throws -> (status: Int, data: Data) {
        lock.withLock {
            refreshedTokens.append(refreshToken)
            return (refreshResponse.0, Data(refreshResponse.1.utf8))
        }
    }

    func getMe(accessToken _: String) async throws -> (status: Int, data: Data) {
        lock.withLock { (getMeResponse.0, Data(getMeResponse.1.utf8)) }
    }
}
