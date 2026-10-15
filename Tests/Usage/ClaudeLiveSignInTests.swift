import Foundation
import Testing

@testable import Refill

/// Refill only reads Claude Code's live sign-in. Claude Code renews it when the user runs `claude`.
@MainActor
struct ClaudeLiveSignInTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func anExpiredLiveSignInStaysExpiredWithoutSendingItsToken() async throws {
        let fixture = try ClaudeLiveSignInFixture()
        defer { fixture.remove() }
        try fixture.claudeCodeWrites(access: "personal-access-1", expiresAt: now.addingTimeInterval(-60))
        var clock = now
        let runtime = ProviderUsageRuntime(connections: [fixture.usage], now: { clock }, onChange: {})

        for _ in 0..<12 {
            await runtime.refreshIfDue()
            clock.addTimeInterval(5 * 60)
        }

        #expect(fixture.server.requests == [])
        #expect(runtime.states.map(\.status) == [.unavailable(.signInExpired, lastSnapshot: nil)])
    }

    @Test
    func aSignInClaudeCodeRenewsItselfIsReadOnTheNextRefresh() async throws {
        let fixture = try ClaudeLiveSignInFixture()
        defer { fixture.remove() }
        try fixture.claudeCodeWrites(access: "personal-access-1", expiresAt: now.addingTimeInterval(-60))
        fixture.server.answer("personal-access-2", sessionPercent: 40)
        var clock = now
        let runtime = ProviderUsageRuntime(connections: [fixture.usage], now: { clock }, onChange: {})
        await runtime.refreshIfDue()

        try fixture.claudeCodeWrites(access: "personal-access-2", expiresAt: now.addingTimeInterval(3_600))
        clock.addTimeInterval(5 * 60)
        await runtime.refreshIfDue()

        #expect(fixture.server.requests == ["personal-access-2"])
        #expect(runtime.states.map(\.sessionPercent) == [40])
    }

    @Test
    func aSignInClaudeCodeClearedShowsSignedOut() async throws {
        let fixture = try ClaudeLiveSignInFixture()
        defer { fixture.remove() }
        try fixture.claudeCodeWrites(access: "", expiresAt: Date(timeIntervalSince1970: 0))
        let runtime = ProviderUsageRuntime(connections: [fixture.usage], now: { [now] in now }, onChange: {})

        await runtime.refreshIfDue()

        #expect(fixture.server.requests == [])
        #expect(runtime.states.map(\.status) == [.unavailable(.signedOut, lastSnapshot: nil)])
    }
}

private extension ProviderUsageState {
    var sessionPercent: Int? {
        guard case let .current(snapshot) = status else { return nil }
        return snapshot.window(.session)?.usedPercent
    }
}

/// A connected `ClaudeCodeUsage` over a temp Claude Code Keychain item and a fake usage server. Every token is fake.
private final class ClaudeLiveSignInFixture: @unchecked Sendable {
    let root: URL
    let server = FakeClaudeUsageServer()
    let usage: ClaudeCodeUsage
    private let suiteName = "ClaudeLiveSignInFixture-\(UUID().uuidString)"

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeLiveSignInFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        let settings = ClaudeUsageSettingsStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        settings.isEnabled = true
        usage = ClaudeCodeUsage(
            settings: settings,
            client: ClaudeUsageClient(
                credentials: ClaudeCredentialsSource(
                    configDirectory: root.appendingPathComponent(".claude", isDirectory: true),
                    keychain: FileClaudeCodeKeychain(fileURL: root.appendingPathComponent("keychain-item.json"))
                ),
                webClient: server
            )
        )
    }

    /// What Claude Code leaves in its Keychain item after `/login`, a renewal, or a rejected renewal.
    func claudeCodeWrites(access: String, expiresAt: Date) throws {
        let expiry = Int(expiresAt.timeIntervalSince1970 * 1_000)
        try JSONSerialization.data(withJSONObject: ["claudeAiOauth": ["accessToken": access, "expiresAt": expiry, "subscriptionType": "max"]])
            .write(to: root.appendingPathComponent("keychain-item.json"))
    }

    func remove() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}
