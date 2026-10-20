import Foundation
import Testing

@testable import rusage

/// Usage reads with rusage's own sign-in. Every token is fake, the store is a temp file, and Claude Code's sign-in is
/// a temp file that the own sign-in must never use.
struct ClaudeOwnSignInUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func anExpiringSignInIsMarkedBeforeItsRefreshTokenIsSent() async {
        let fixture = ClaudeOwnSignInUsageFixture()
        defer { fixture.remove() }
        fixture.signedIn(access: "a1", refresh: "r1", expiresAt: now.addingTimeInterval(60))
        fixture.usageServer.answer("a2", sessionPercent: 40)

        #expect(await fixture.usage.readUsage(now: now).sessionPercent == 40)
        #expect(fixture.log.events == ["save(a1, pending: true)", "refresh(r1)", "save(a2, pending: false)", "usage(a2)"])
    }

    @Test
    func aRenewedPairTheStoreRefusedIsSavedOnTheNextReadWithoutASecondRefresh() async {
        let fixture = ClaudeOwnSignInUsageFixture()
        defer { fixture.remove() }
        fixture.signedIn(access: "a1", refresh: "r1", expiresAt: now.addingTimeInterval(60))
        fixture.usageServer.answer("a2", sessionPercent: 40)
        fixture.store.answerSaves([true, false, false])

        #expect(await fixture.usage.readUsage(now: now).sessionPercent == 40)
        #expect(await fixture.usage.readUsage(now: now).sessionPercent == 40)

        #expect(fixture.tokenServer.refreshes == ["r1"])
        #expect(fixture.usageServer.requests == ["a2", "a2"])
        #expect(fixture.files.store.read(allowingPrompt: false)
            == .found(.fake(access: "a2", refresh: "r2", expiresAt: now.addingTimeInterval(3_600)), refreshPending: false))
    }

    @Test
    func aRejectedRefreshTokenDeletesOnlyRUsagesSignInAndNeverFallsBackToClaudeCode() async throws {
        let fixture = ClaudeOwnSignInUsageFixture(tokenGeneration: 2)
        defer { fixture.remove() }
        fixture.signedIn(access: "a1", refresh: "r1", expiresAt: now)
        try fixture.claudeCodeSignsIn(access: "claude-code-access", expiresAt: now.addingTimeInterval(3_600))
        fixture.usageServer.answer("claude-code-access", sessionPercent: 10)

        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signInRequired))
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signInRequired))

        #expect(fixture.tokenServer.refreshes == ["r1"])
        #expect(fixture.usageServer.requests == [])
        #expect(fixture.files.store.read(allowingPrompt: false) == .notFound)
        #expect(FileManager.default.fileExists(atPath: fixture.claudeCodeItem.path))
    }

    @Test
    func aRejectedAccessTokenIsRenewedOnceAndRetried() async {
        let fixture = ClaudeOwnSignInUsageFixture()
        defer { fixture.remove() }
        fixture.signedIn(access: "a1", refresh: "r1", expiresAt: now.addingTimeInterval(3_600))
        fixture.usageServer.answer("a2", sessionPercent: 40)

        #expect(await fixture.usage.readUsage(now: now).sessionPercent == 40)
        #expect(fixture.tokenServer.refreshes == ["r1"])
        #expect(fixture.usageServer.requests == ["a1", "a2"])
    }

    @Test
    func aRenewedTokenAnthropicAlsoRejectsNeedsANewSignIn() async {
        let fixture = ClaudeOwnSignInUsageFixture()
        defer { fixture.remove() }
        fixture.signedIn(access: "a1", refresh: "r1", expiresAt: now.addingTimeInterval(3_600))

        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signInRequired))
        #expect(fixture.tokenServer.refreshes == ["r1"])
        #expect(fixture.usageServer.requests == ["a1", "a2"])
    }

    @Test
    func signingInConnectsClaudeWithThePlanAndEmailAndSigningOutGoesBackToClaudeCode() async throws {
        let fixture = ClaudeOwnSignInUsageFixture(usesOwnSignIn: false)
        defer { fixture.remove() }
        fixture.flow.answer(.success(.fake(access: "a1", refresh: "r1", expiresAt: now.addingTimeInterval(3_600))))
        fixture.usageServer.profile = ClaudeProfile(planName: "max_20x", email: "sam@example.com")
        fixture.usageServer.answer("a1", sessionPercent: 12)

        try await fixture.usage.signIn()

        #expect(fixture.settings.isEnabled && fixture.settings.usesOwnSignIn)
        #expect(fixture.usage.ownSignIn == .signedIn)
        guard case let .snapshot(snapshot) = await fixture.usage.readUsage(now: now) else {
            Issue.record("Expected usage with rusage's own sign-in")
            return
        }
        #expect(snapshot.planName == "max_20x")
        #expect(snapshot.accountEmail == "sam@example.com")

        try await fixture.usage.signOut()

        #expect(fixture.usage.ownSignIn == .signedOut)
        #expect(fixture.files.store.read(allowingPrompt: false) == .notFound)
        #expect(fixture.tokenServer.revoked == ["r1"])
        #expect(await fixture.usage.readUsage(now: now) == .unavailable(.signedOut))
    }

    @Test
    func aSignInTheKeychainRefusedLastsUntilQuitAndADeclinedOneChangesNothing() async throws {
        let declined = ClaudeOwnSignInUsageFixture(usesOwnSignIn: false)
        defer { declined.remove() }
        declined.flow.answer(.failure(.denied))

        await #expect(throws: ProviderNotice(title: "Claude sign-in declined", detail: "Sign in again to see your limits.")) {
            try await declined.usage.signIn()
        }
        #expect(!declined.settings.isEnabled && !declined.settings.usesOwnSignIn)

        let refused = ClaudeOwnSignInUsageFixture(usesOwnSignIn: false)
        defer { refused.remove() }
        refused.flow.answer(.success(.fake(access: "a1", refresh: "r1", expiresAt: now.addingTimeInterval(3_600))))
        refused.usageServer.answer("a1", sessionPercent: 12)
        refused.store.answerSaves([], thenAccept: false)

        await #expect(throws: ProviderNotice(title: "Claude sign-in not saved", detail: "It lasts until rusage quits.")) {
            try await refused.usage.signIn()
        }
        #expect(refused.settings.usesOwnSignIn)
        #expect(await refused.usage.readUsage(now: now).sessionPercent == 12)
    }

    @Test
    func disconnectingSignsOutOfRUsagesOwnSignIn() async {
        let fixture = ClaudeOwnSignInUsageFixture()
        defer { fixture.remove() }
        fixture.signedIn(access: "a1", refresh: "r1", expiresAt: now.addingTimeInterval(3_600))

        await fixture.usage.disconnect()

        #expect(!fixture.settings.isEnabled && !fixture.settings.usesOwnSignIn)
        #expect(fixture.files.store.read(allowingPrompt: false) == .notFound)
        #expect(fixture.tokenServer.revoked == ["r1"])
    }
}

private extension UsageProviderReading {
    var sessionPercent: Int? {
        guard case let .snapshot(snapshot) = self else { return nil }
        return snapshot.window(.session)?.usedPercent
    }
}

/// A connected `ClaudeCodeUsage` over rusage's own sign-in in temp files, a fake token server and a fake usage server
/// that log to one stream, and Claude Code's sign-in as a temp file.
private final class ClaudeOwnSignInUsageFixture: @unchecked Sendable {
    let files = ClaudeOwnSignInFiles()
    let log = ClaudeEventLog()
    let flow = ScriptedClaudeSignInFlow()
    let store: RecordingClaudeSignInStore
    let tokenServer: FakeClaudeTokenServer
    let usageServer: FakeClaudeUsageServer
    let settings: ClaudeUsageSettingsStore
    let usage: ClaudeCodeUsage
    private let suiteName = "ClaudeOwnSignInUsageFixture-\(UUID().uuidString)"

    init(tokenGeneration: Int = 1, usesOwnSignIn: Bool = true) {
        try? FileManager.default.createDirectory(at: files.root, withIntermediateDirectories: true)
        store = RecordingClaudeSignInStore(file: files.store, log: log)
        tokenServer = FakeClaudeTokenServer(generation: tokenGeneration, log: log)
        usageServer = FakeClaudeUsageServer(log: log)
        settings = ClaudeUsageSettingsStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        settings.isEnabled = usesOwnSignIn
        settings.usesOwnSignIn = usesOwnSignIn
        usage = ClaudeCodeUsage(
            settings: settings,
            client: ClaudeUsageClient(
                credentials: ClaudeCredentialsSource(
                    configDirectory: files.root.appendingPathComponent(".claude", isDirectory: true),
                    keychain: FileClaudeCodeKeychain(fileURL: files.root.appendingPathComponent("claude-code-item.json"))
                ),
                ownSignIn: ClaudeOwnSignIn(store: store, tokenEndpoint: tokenServer, lock: files.lock),
                webClient: usageServer
            ),
            signInFlow: flow
        )
    }

    var claudeCodeItem: URL {
        files.root.appendingPathComponent("claude-code-item.json")
    }

    func signedIn(access: String, refresh: String, expiresAt: Date) {
        _ = files.store.save(.fake(access: access, refresh: refresh, expiresAt: expiresAt), refreshPending: false, allowingPrompt: false)
    }

    func claudeCodeSignsIn(access: String, expiresAt: Date) throws {
        let expiry = Int(expiresAt.timeIntervalSince1970 * 1_000)
        try JSONSerialization.data(withJSONObject: ["claudeAiOauth": ["accessToken": access, "expiresAt": expiry, "subscriptionType": "max"]])
            .write(to: claudeCodeItem)
    }

    func remove() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        files.remove()
    }
}
