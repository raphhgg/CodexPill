import Foundation
import Testing

@testable import CodexPill

/// Claude Code renews its own expired live sign-in when CodexPill runs `claude doctor`. CodexPill never writes it.
@MainActor
struct ClaudeLiveRenewalTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func anExpiredLiveSignInIsRenewedByClaudeCodeThenReadAgain() async throws {
        let fixture = try ClaudeLiveRenewalFixture(now: now)
        defer { fixture.remove() }
        try fixture.signIn(access: "personal-access-1", expiresAt: now.addingTimeInterval(-60))
        fixture.claude.renewClaudeCode = { [fixture] in try? fixture.claudeCodeRenews(access: "personal-access-2") }
        fixture.server.answer("personal-access-2", sessionPercent: 40)
        let runtime = ProviderUsageRuntime(connections: [fixture.usage], now: { [now] in now }, onChange: {})
        await runtime.refreshIfDue()

        await runtime.renewLiveSignInsIfNeeded()

        #expect(fixture.claude.commands == ["doctor in default"])
        #expect(fixture.server.requests == ["personal-access-2"])
        #expect(runtime.states.map(\.sessionPercent) == [40])
    }

    @Test
    func theLiveSignInIsNotRenewedWhileClaudeCodeRuns() async throws {
        let fixture = try ClaudeLiveRenewalFixture(now: now)
        defer { fixture.remove() }
        try fixture.signIn(access: "personal-access-1", expiresAt: now.addingTimeInterval(-60))
        fixture.claude.renewClaudeCode = { [fixture] in try? fixture.claudeCodeRenews(access: "personal-access-2") }
        fixture.processes.isRunning = true

        #expect(await fixture.usage.renewLiveSignInIfNeeded(now: now) == false)
        #expect(fixture.claude.commands == [])

        fixture.processes.isRunning = false
        #expect(await fixture.usage.renewLiveSignInIfNeeded(now: now) == true)
        #expect(fixture.claude.commands == ["doctor in default"])
    }

    @Test
    func theLiveSignInIsNotRenewedBeforeItExpires() async throws {
        let fixture = try ClaudeLiveRenewalFixture(now: now)
        defer { fixture.remove() }
        try fixture.signIn(access: "personal-access-1", expiresAt: now.addingTimeInterval(60))

        #expect(await fixture.usage.renewLiveSignInIfNeeded(now: now) == false)
        #expect(fixture.claude.commands == [])

        #expect(await fixture.usage.renewLiveSignInIfNeeded(now: now.addingTimeInterval(60)) == false)
        #expect(fixture.claude.commands == ["doctor in default"])
    }

    @Test
    func aLiveSignInClaudeCodeCannotRenewIsRetriedOnlyAfterHalfAnHour() async throws {
        let fixture = try ClaudeLiveRenewalFixture(now: now)
        defer { fixture.remove() }
        try fixture.signIn(access: "personal-access-1", expiresAt: now.addingTimeInterval(-60))

        _ = await fixture.usage.renewLiveSignInIfNeeded(now: now)
        _ = await fixture.usage.renewLiveSignInIfNeeded(now: now.addingTimeInterval(10 * 60))
        #expect(fixture.claude.commands == ["doctor in default"])

        _ = await fixture.usage.renewLiveSignInIfNeeded(now: now.addingTimeInterval(31 * 60))
        #expect(fixture.claude.commands == ["doctor in default", "doctor in default"])
    }
}

private extension ProviderUsageState {
    var sessionPercent: Int? {
        guard case let .current(snapshot) = status else { return nil }
        return snapshot.window(.session)?.usedPercent
    }
}

/// A connected `ClaudeCodeUsage` over a temp Claude Code sign-in, a fake `claude` and a fake usage server. Every token
/// is fake.
private final class ClaudeLiveRenewalFixture: @unchecked Sendable {
    let root: URL
    let claude = FakeClaudeCode()
    let server = FakeClaudeUsageServer()
    let processes = ClaudeCodeProcessProbe()
    let usage: ClaudeCodeUsage
    private let suiteName = "ClaudeLiveRenewalFixture-\(UUID().uuidString)"
    private let now: Date

    init(now: Date) throws {
        self.now = now
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeLiveRenewalFixture-\(UUID().uuidString)", isDirectory: true)
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
            ),
            commands: ClaudeCodeCommands(processes: claude),
            processes: processes
        )
    }

    /// What Claude Code leaves after `/login`: its Keychain item.
    func signIn(access: String, expiresAt: Date) throws {
        try credentials(access: access, expiresAt: expiresAt).write(to: root.appendingPathComponent("keychain-item.json"))
    }

    /// What Claude Code does when it renews its own sign-in: it rewrites its Keychain item.
    func claudeCodeRenews(access: String) throws {
        try credentials(access: access, expiresAt: now.addingTimeInterval(3_600)).write(to: root.appendingPathComponent("keychain-item.json"))
    }

    func remove() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    private func credentials(access: String, expiresAt: Date) -> Data {
        let expiry = Int(expiresAt.timeIntervalSince1970 * 1_000)
        return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": ["accessToken": access, "expiresAt": expiry, "subscriptionType": "max"]])
    }
}
