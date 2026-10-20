import Foundation
import Testing

@testable import RUsage

/// The renewal of rusage's own sign-in never sends a refresh token twice, even across processes or after a crash.
struct ClaudeOwnSignInTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func aRenewalThatNeverSavedItsResultIsNotRetriedOnTheNextLaunch() async {
        let files = ClaudeOwnSignInFiles()
        defer { files.remove() }
        _ = files.store.save(.fake(access: "a1", refresh: "r1", expiresAt: now.addingTimeInterval(60)), refreshPending: false, allowingPrompt: false)
        let server = FakeClaudeTokenServer()
        let crashingStore = RecordingClaudeSignInStore(file: files.store)
        crashingStore.answerSaves([true], thenAccept: false)
        let launchA = ClaudeOwnSignIn(store: crashingStore, tokenEndpoint: server, lock: files.lock)

        #expect(await launchA.token(now: now, allowingPrompt: false) == .token(.fake(access: "a2", refresh: "r2", expiresAt: now.addingTimeInterval(3_600))))

        let launchB = ClaudeOwnSignIn(store: files.store, tokenEndpoint: server, lock: files.lock)

        #expect(await launchB.token(now: now, allowingPrompt: false) == .signInRequired)
        #expect(server.refreshes == ["r1"])
        #expect(files.store.read(allowingPrompt: false) == .notFound)
    }

    @Test
    func twoProcessesRenewingAtOnceSendTheRefreshTokenOnce() async {
        let files = ClaudeOwnSignInFiles()
        defer { files.remove() }
        _ = files.store.save(.fake(access: "a1", refresh: "r1", expiresAt: now.addingTimeInterval(60)), refreshPending: false, allowingPrompt: false)
        let server = FakeClaudeTokenServer()
        server.answer(after: .milliseconds(300))
        let processA = ClaudeOwnSignIn(store: files.store, tokenEndpoint: server, lock: ClaudeRefreshLock(fileURL: files.lock.fileURL))
        let processB = ClaudeOwnSignIn(store: files.store, tokenEndpoint: server, lock: ClaudeRefreshLock(fileURL: files.lock.fileURL))

        async let tokenA = processA.token(now: now, allowingPrompt: false)
        async let tokenB = processB.token(now: now, allowingPrompt: false)
        let renewed = ClaudeSignIn.fake(access: "a2", refresh: "r2", expiresAt: now.addingTimeInterval(3_600))

        #expect(await [tokenA, tokenB] == [.token(renewed), .token(renewed)])
        #expect(server.refreshes == ["r1"])
        #expect(files.store.read(allowingPrompt: false) == .found(renewed, refreshPending: false))
    }

    @Test
    func aFailedRenewalKeepsTheUnexpiredTokenAndClearsTheMarker() async {
        let files = ClaudeOwnSignInFiles()
        defer { files.remove() }
        let current = ClaudeSignIn.fake(access: "a1", refresh: "r1", expiresAt: now.addingTimeInterval(60))
        _ = files.store.save(current, refreshPending: false, allowingPrompt: false)
        let server = FakeClaudeTokenServer()
        server.fail(with: .transport)
        let ownSignIn = ClaudeOwnSignIn(store: files.store, tokenEndpoint: server, lock: files.lock)

        #expect(await ownSignIn.token(now: now, allowingPrompt: false) == .token(current))
        #expect(files.store.read(allowingPrompt: false) == .found(current, refreshPending: false))
        #expect(await ownSignIn.token(now: now.addingTimeInterval(60), allowingPrompt: false) == .unavailable(.network))

        server.fail(with: nil)

        #expect(await ownSignIn.token(now: now.addingTimeInterval(60), allowingPrompt: false)
            == .token(.fake(access: "a2", refresh: "r2", expiresAt: now.addingTimeInterval(3_660))))
        #expect(server.refreshes == ["r1", "r1", "r1"])
    }

    @Test
    func noRefreshTokenIsSentWhenTheMarkerCannotBeSaved() async {
        let files = ClaudeOwnSignInFiles()
        defer { files.remove() }
        _ = files.store.save(.fake(access: "a1", refresh: "r1", expiresAt: now), refreshPending: false, allowingPrompt: false)
        let server = FakeClaudeTokenServer()
        let refusingStore = RecordingClaudeSignInStore(file: files.store)
        refusingStore.answerSaves([], thenAccept: false)
        let ownSignIn = ClaudeOwnSignIn(store: refusingStore, tokenEndpoint: server, lock: files.lock)

        #expect(await ownSignIn.token(now: now, allowingPrompt: false) == .unavailable(.saveFailed))
        #expect(server.refreshes == [])
    }

    @Test
    func signingOutDeletesTheItemAndRevokesItsRefreshToken() async {
        let files = ClaudeOwnSignInFiles()
        defer { files.remove() }
        let server = FakeClaudeTokenServer()
        let ownSignIn = ClaudeOwnSignIn(store: files.store, tokenEndpoint: server, lock: files.lock)

        #expect(await ownSignIn.store(.fake(access: "a1", refresh: "r1", expiresAt: now.addingTimeInterval(3_600))))
        #expect(await ownSignIn.signOut())
        #expect(files.store.read(allowingPrompt: false) == .notFound)
        #expect(server.revoked == ["r1"])
        #expect(await ownSignIn.token(now: now, allowingPrompt: false) == .signInRequired)
    }
}
