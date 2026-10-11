import Foundation
import Testing

@testable import CodexPill

/// Claude accounts that work like Codex accounts: added through Claude Code's own login in a throwaway folder, read
/// with their own saved sign-in, renewed by Claude Code, and switched with the live sign-in saved first.
@MainActor
struct ClaudeAccountsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func claudeCodeNamesAThrowawayFoldersKeychainItemAfterItsPath() {
        #expect(ClaudeCodeCommands.keychainService(forConfigDirectory: "/tmp/claude-config") == "Claude Code-credentials-19aa18c8")
    }

    @Test
    func addingAnAccountRunsClaudeCodesLoginInAThrowawayFolderAndSavesIt() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1")
        let liveBefore = try fixture.liveFiles()
        fixture.claude.login = .signsIn(credentials: fixture.credentials(access: "team-access-1"), globalConfig: fixture.globalConfig(.team))

        #expect(try await fixture.usage.addAccount() == true)

        #expect(try await fixture.usage.savedAccounts().map(\.email) == ["personal@example.com", "team@example.com"])
        #expect(try fixture.savedAccessToken(of: "team@example.com") == "team-access-1")
        #expect(fixture.claude.commands == ["auth login --claudeai in sign-in-1"])
        #expect(fixture.claude.deletedServices == [FakeClaudeCode.service(for: fixture.folder("sign-in-1").path)])
        #expect(fixture.claude.remainingItems == [])
        #expect(try fixture.throwawayFolders() == [])
        #expect(try fixture.liveFiles() == liveBefore)
    }

    @Test
    func cancellingTheSignInSavesNothingAndCleansUp() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1")
        let gate = TestGate()
        fixture.claude.login = .waitsForBrowser(gate, credentials: fixture.credentials(access: "team-access-1"), globalConfig: fixture.globalConfig(.team))

        let usage = fixture.usage
        let signIn = Task { try await usage.addAccount() }
        await gate.waitUntilReached()
        signIn.cancel()

        #expect(try await signIn.value == false)
        #expect(try await fixture.usage.savedAccounts().map(\.email) == ["personal@example.com"])
        #expect(fixture.claude.deletedServices == [FakeClaudeCode.service(for: fixture.folder("sign-in-1").path)])
        #expect(try fixture.throwawayFolders() == [])
    }

    @Test
    func aFailedSignInSavesNothingAndDeletesWhatClaudeCodeLeftBehind() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1")
        fixture.claude.login = .savesThenFails(credentials: fixture.credentials(access: "team-access-1"))

        await #expect(throws: ProviderNotice(title: "Claude sign-in didn't finish", detail: "Nothing was saved.")) {
            try await fixture.usage.addAccount()
        }
        #expect(try await fixture.usage.savedAccounts().map(\.email) == ["personal@example.com"])
        #expect(fixture.claude.remainingItems == [])
        #expect(try fixture.throwawayFolders() == [])
    }

    @Test
    func aSignInWithoutAnAccountRecordIsNotSaved() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1")
        fixture.claude.login = .signsIn(credentials: fixture.credentials(access: "team-access-1"), globalConfig: Data("{}".utf8))

        await #expect(throws: ProviderNotice(title: "Unknown Claude account", detail: "Nothing was saved.")) {
            try await fixture.usage.addAccount()
        }
        #expect(try await fixture.usage.savedAccounts().map(\.email) == ["personal@example.com"])
        #expect(try fixture.throwawayFolders() == [])
    }

    @Test
    func withoutClaudeCodeInstalledAddingIsUnavailable() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        fixture.claude.isInstalled = false

        #expect(fixture.usage.signInAvailability == .notInstalled)
        await #expect(throws: ProviderNotice(title: "Install Claude Code first", detail: nil)) {
            try await fixture.usage.addAccount()
        }
        #expect(fixture.claude.commands == [])
    }

    @Test
    func whenClaudeCodeHasNoSignInAddingSignsClaudeCodeItselfIn() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        fixture.claude.signInClaudeCode = { [fixture] in try fixture.signInLive(.team, access: "team-access-1") }

        #expect(try await fixture.usage.addAccount() == true)

        #expect(fixture.claude.commands == ["auth login --claudeai in default"])
        #expect(try await fixture.usage.savedAccounts().map { "\($0.email ?? "") \($0.isActive)" } == ["team@example.com true"])
    }

    @Test
    func anInactiveAccountIsReadWithItsOwnSavedSignIn() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1")
        let team = try fixture.saveAccount(.team, access: "team-access-1", expiresAt: now.addingTimeInterval(3_600))
        fixture.server.answer("team-access-1", sessionPercent: 64)

        await fixture.usage.refreshInactiveAccount(team, now: now)

        let saved = try await fixture.usage.savedAccounts()
        #expect(saved.map { $0.usage?.window(.session)?.usedPercent } == [nil, 64])
        #expect(saved.last?.usage?.fetchedAt == now)
        #expect(fixture.server.requests == ["team-access-1"])
        #expect(fixture.claude.commands == [])
    }

    @Test
    func anExpiredSavedSignInIsRenewedByClaudeCodeThenSavedAndRead() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1")
        let liveBefore = try fixture.liveFiles()
        let team = try fixture.saveAccount(.team, access: "team-access-1", expiresAt: now.addingTimeInterval(-60))
        fixture.claude.renewal = .renews(credentials: fixture.credentials(access: "team-access-2"))
        fixture.server.answer("team-access-2", sessionPercent: 30)

        await fixture.usage.refreshInactiveAccount(team, now: now)

        #expect(fixture.claude.commands == ["doctor in sign-in-1"])
        #expect(try fixture.savedAccessToken(of: "team@example.com") == "team-access-2")
        #expect(fixture.server.requests == ["team-access-2"])
        #expect(try await fixture.usage.savedAccounts().last?.usage?.window(.session)?.usedPercent == 30)
        #expect(fixture.claude.remainingItems == [])
        #expect(try fixture.throwawayFolders() == [])
        #expect(try fixture.liveFiles() == liveBefore)
    }

    @Test
    func aRenewalIsDroppedWhenTheSavedCopyChangedMeanwhile() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1")
        let team = try fixture.saveAccount(.team, access: "team-access-1", expiresAt: now.addingTimeInterval(-60))
        let newer = fixture.credentials(access: "team-access-3")
        fixture.claude.renewal = .renews(credentials: fixture.credentials(access: "team-access-2"), meanwhile: { [fixture] in
            _ = try? fixture.saveAccount(.team, credentials: newer)
        })

        await fixture.usage.refreshInactiveAccount(team, now: now)

        #expect(try fixture.savedAccessToken(of: "team@example.com") == "team-access-3")
        #expect(fixture.server.requests == [])
    }

    @Test
    func whenClaudeCodeRenewsNothingTheAccountKeepsItsLastLimits() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1")
        let team = try fixture.saveAccount(.team, access: "team-access-1", expiresAt: now.addingTimeInterval(3_600))
        fixture.server.answer("team-access-1", sessionPercent: 64)
        await fixture.usage.refreshInactiveAccount(team, now: now)

        let later = now.addingTimeInterval(2 * 3_600)
        await fixture.usage.refreshInactiveAccount(team, now: later)

        #expect(fixture.claude.commands == ["doctor in sign-in-1"])
        let usage = try await fixture.usage.savedAccounts().last?.usage
        #expect(usage?.window(.session)?.usedPercent == 64)
        #expect(usage?.fetchedAt == now)
    }

    @Test
    func theActiveAccountIsNeverRenewedOrReadAsAnInactiveOne() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1")
        let personal = try #require(try await fixture.usage.savedAccounts().first?.id)
        try fixture.expireSavedSignIn(of: personal)

        await fixture.usage.refreshInactiveAccount(personal, now: now)

        #expect(fixture.claude.commands == [])
        #expect(fixture.server.requests == [])
    }

    @Test
    func switchingToAnAccountWhileClaudeCodeRenewsItActivatesTheRenewedSignIn() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1")
        let team = try fixture.saveAccount(.team, access: "team-access-1", expiresAt: now.addingTimeInterval(-60))
        let gate = TestGate()
        fixture.claude.renewal = .renewsAfter(gate, credentials: fixture.credentials(access: "team-access-2"))
        let runtime = ProviderUsageRuntime(connections: [fixture.usage], now: { [now] in now }, onChange: {})

        let inactiveRefresh = Task { await runtime.refreshInactiveAccountsIfDue() }
        await gate.waitUntilReached()
        let switchStarted = SwitchStarted()
        let switchToTeam = Task {
            switchStarted.value = true
            return await runtime.perform(.switchAccount(team), on: .claude)
        }
        while !switchStarted.value {
            await Task.yield()
        }
        await gate.open()

        #expect(await switchToTeam.value == nil)
        await inactiveRefresh.value
        #expect(try fixture.liveAccessToken() == "team-access-2")
        #expect(try fixture.savedAccessToken(of: "team@example.com") == "team-access-2")
    }

    @Test
    func switchingAwaySavesTheSignInClaudeCodeRotatedFirst() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1")
        let team = try fixture.saveAccount(.team, access: "team-access-1", expiresAt: now.addingTimeInterval(3_600))
        try fixture.signInLive(.personal, access: "personal-access-2")

        try await fixture.usage.switchAccount(to: team)

        #expect(try fixture.savedAccessToken(of: "personal@example.com") == "personal-access-2")
        #expect(try fixture.liveAccessToken() == "team-access-1")
    }

    @Test
    func anExpiredLiveSignInIsRenewedByClaudeCodeThenReadAgain() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1", expiresAt: now.addingTimeInterval(-60))
        fixture.claude.renewClaudeCode = { [fixture] in try? fixture.renewLive(access: "personal-access-2") }
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
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1", expiresAt: now.addingTimeInterval(-60))
        fixture.claude.renewClaudeCode = { [fixture] in try? fixture.renewLive(access: "personal-access-2") }
        fixture.processes.isRunning = true

        #expect(await fixture.usage.renewLiveSignInIfNeeded(now: now) == false)
        #expect(fixture.claude.commands == [])

        fixture.processes.isRunning = false
        #expect(await fixture.usage.renewLiveSignInIfNeeded(now: now) == true)
        #expect(fixture.claude.commands == ["doctor in default"])
    }

    @Test
    func theLiveSignInIsNotRenewedBeforeItExpires() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1", expiresAt: now.addingTimeInterval(60))

        #expect(await fixture.usage.renewLiveSignInIfNeeded(now: now) == false)
        #expect(fixture.claude.commands == [])

        #expect(await fixture.usage.renewLiveSignInIfNeeded(now: now.addingTimeInterval(60)) == false)
        #expect(fixture.claude.commands == ["doctor in default"])
    }

    @Test
    func aLiveSignInClaudeCodeCannotRenewIsRetriedOnlyAfterHalfAnHour() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1", expiresAt: now.addingTimeInterval(-60))

        _ = await fixture.usage.renewLiveSignInIfNeeded(now: now)
        _ = await fixture.usage.renewLiveSignInIfNeeded(now: now.addingTimeInterval(10 * 60))
        #expect(fixture.claude.commands == ["doctor in default"])

        _ = await fixture.usage.renewLiveSignInIfNeeded(now: now.addingTimeInterval(31 * 60))
        #expect(fixture.claude.commands == ["doctor in default", "doctor in default"])
    }

    @Test
    func theLiveSignInIsNotRenewedWhileAnAccountIsBeingAdded() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1", expiresAt: now.addingTimeInterval(-60))
        let gate = TestGate()
        fixture.claude.login = .waitsForBrowser(gate, credentials: fixture.credentials(access: "team-access-1"), globalConfig: fixture.globalConfig(.team))
        let runtime = ProviderUsageRuntime(connections: [fixture.usage], now: { [now] in now }, onChange: {})
        await runtime.refreshIfDue()

        let add = Task { await runtime.perform(.addAccount, on: .claude) }
        await gate.waitUntilReached()
        await runtime.renewLiveSignInsIfNeeded()
        #expect(fixture.claude.commands == ["auth login --claudeai in sign-in-1"])

        await gate.open()
        #expect(await add.value == nil)
        await runtime.renewLiveSignInsIfNeeded()
        #expect(fixture.claude.commands == ["auth login --claudeai in sign-in-1", "doctor in default"])
    }

    @Test
    func theLiveSignInIsNotRenewedWhileTheCurrentSignInIsBeingSaved() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1", expiresAt: now.addingTimeInterval(-60))
        let runtime = ProviderUsageRuntime(connections: [fixture.usage], now: { [now] in now }, onChange: {})
        await runtime.refreshIfDue()
        let saveReached = LockedFlag()
        let releaseSave = DispatchSemaphore(value: 0)
        fixture.items.beforeSave = {
            saveReached.set()
            _ = releaseSave.wait(timeout: .now() + 5)
        }

        let save = Task { await runtime.perform(.saveCurrentAccount, on: .claude) }
        while !saveReached.isSet {
            await Task.yield()
        }
        await runtime.renewLiveSignInsIfNeeded()
        fixture.items.beforeSave = nil
        releaseSave.signal()

        #expect(await save.value == nil)
        #expect(fixture.claude.commands == [])
    }

    @Test
    func inactiveAccountsAreNotReadWhileClaudeCodeRenewsItsLiveSignIn() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1", expiresAt: now.addingTimeInterval(-60))
        try fixture.saveAccount(.team, access: "team-access-1", expiresAt: now.addingTimeInterval(3_600))
        fixture.server.answer("team-access-1", sessionPercent: 64)
        let gate = TestGate()
        fixture.claude.renewClaudeCode = { await gate.pass() }
        let runtime = ProviderUsageRuntime(connections: [fixture.usage], now: { [now] in now }, onChange: {})
        await runtime.refreshIfDue()

        let renewal = Task { await runtime.renewLiveSignInsIfNeeded() }
        await gate.waitUntilReached()
        await runtime.refreshInactiveAccountsIfDue()
        #expect(fixture.server.requests == [])

        await gate.open()
        await renewal.value
        await runtime.refreshInactiveAccountsIfDue()
        #expect(fixture.server.requests == ["team-access-1"])
    }

    @Test
    func switchingWaitsForClaudeCodeToRenewItsLiveSignInAndSavesTheRenewedOne() async throws {
        let fixture = try ClaudeAccountsFixture(now: now)
        defer { fixture.remove() }
        try fixture.signInLive(.personal, access: "personal-access-1", expiresAt: now.addingTimeInterval(-60))
        let team = try fixture.saveAccount(.team, access: "team-access-1", expiresAt: now.addingTimeInterval(3_600))
        let gate = TestGate()
        fixture.claude.renewClaudeCode = { [fixture] in
            await gate.pass()
            try? fixture.renewLive(access: "personal-access-2")
        }
        let runtime = ProviderUsageRuntime(connections: [fixture.usage], now: { [now] in now }, onChange: {})
        await runtime.refreshIfDue()

        let renewal = Task { await runtime.renewLiveSignInsIfNeeded() }
        await gate.waitUntilReached()
        let switchStarted = SwitchStarted()
        let switchToTeam = Task {
            switchStarted.value = true
            return await runtime.perform(.switchAccount(team), on: .claude)
        }
        while !switchStarted.value {
            await Task.yield()
        }
        // A switch that did not wait would finish here, before Claude Code writes its renewed sign-in.
        try await Task.sleep(for: .milliseconds(100))
        await gate.open()

        #expect(await switchToTeam.value == nil)
        await renewal.value
        #expect(try fixture.savedAccessToken(of: "personal@example.com") == "personal-access-2")
        #expect(try fixture.liveAccessToken() == "team-access-1")
    }
}

private extension ProviderUsageState {
    var sessionPercent: Int? {
        guard case let .current(snapshot) = status else { return nil }
        return snapshot.window(.session)?.usedPercent
    }
}

@MainActor
private final class SwitchStarted {
    var value = false
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() {
        lock.withLock { value = true }
    }
}

private enum ClaudeTestAccount {
    case personal
    case team

    var email: String {
        switch self {
        case .personal: "personal@example.com"
        case .team: "team@example.com"
        }
    }

    var record: [String: Any] {
        switch self {
        case .personal: ["accountUuid": "user-uuid", "organizationUuid": "personal-org-uuid", "emailAddress": email]
        case .team: ["accountUuid": "user-uuid", "organizationUuid": "team-org-uuid", "emailAddress": email]
        }
    }
}

/// A `ClaudeCodeUsage` over a temp home, fake Keychain items, a fake `claude` and a fake usage server. Every token is fake.
private final class ClaudeAccountsFixture: @unchecked Sendable {
    let root: URL
    let claude = FakeClaudeCode()
    let server = FakeClaudeUsageServer()
    let liveKeychain: FileClaudeCodeKeychain
    let items: FileClaudeCodeAccountItems
    let processes = ClaudeCodeProcessProbe()
    let store: ClaudeCodeAccountStore
    let usage: ClaudeCodeUsage
    private let suiteName = "ClaudeAccountsFixture-\(UUID().uuidString)"
    private let now: Date

    init(now: Date) throws {
        self.now = now
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeAccountsFixture-\(UUID().uuidString)", isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let codexPill = root.appendingPathComponent("codexpill", isDirectory: true)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexPill, withIntermediateDirectories: true)
        liveKeychain = FileClaudeCodeKeychain(fileURL: codexPill.appendingPathComponent(FileClaudeCodeKeychain.fileName))
        items = FileClaudeCodeAccountItems(rootDirectory: codexPill)
        store = ClaudeCodeAccountStore(
            catalogFile: codexPill.appendingPathComponent("claude-code-accounts.json"),
            items: items,
            claudeCode: ClaudeCodeSignInStore(
                configDirectory: home.appendingPathComponent(".claude", isDirectory: true),
                globalConfigFile: home.appendingPathComponent(".claude.json"),
                keychain: liveKeychain
            ),
            processes: processes
        )
        let settings = ClaudeUsageSettingsStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        settings.isEnabled = true
        let counter = FolderCounter()
        usage = ClaudeCodeUsage(
            settings: settings,
            client: ClaudeUsageClient(
                credentials: ClaudeCredentialsSource(configDirectory: home.appendingPathComponent(".claude", isDirectory: true), keychain: liveKeychain),
                webClient: server
            ),
            accounts: store,
            commands: ClaudeCodeCommands(
                processes: claude,
                keychain: claude,
                root: root.appendingPathComponent("throwaway", isDirectory: true),
                newFolderName: { "sign-in-\(counter.next())" }
            )
        )
    }

    var liveKeychainFile: URL { root.appendingPathComponent("codexpill/\(FileClaudeCodeKeychain.fileName)") }
    var globalConfigFile: URL { root.appendingPathComponent("home/.claude.json") }

    func folder(_ name: String) -> URL {
        root.appendingPathComponent("throwaway/\(name)", isDirectory: true)
    }

    func credentials(access: String, expiresAt: Date? = nil) -> Data {
        let expiry = Int((expiresAt ?? now.addingTimeInterval(3_600)).timeIntervalSince1970 * 1_000)
        let oauth: [String: Any] = [
            "accessToken": access, "refreshToken": "\(access)-renewal", "expiresAt": expiry,
            "scopes": ["user:inference", "user:profile"], "subscriptionType": "max",
        ]
        return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
    }

    func globalConfig(_ account: ClaudeTestAccount) -> Data {
        try! JSONSerialization.data(withJSONObject: ["oauthAccount": account.record])
    }

    /// What Claude Code leaves after `/login`: its Keychain item and the account record, saved in CodexPill.
    func signInLive(_ account: ClaudeTestAccount, access: String, expiresAt: Date? = nil) throws {
        try credentials(access: access, expiresAt: expiresAt).write(to: liveKeychainFile)
        try globalConfig(account).write(to: globalConfigFile)
        try store.captureCurrent()
    }

    /// What Claude Code does when it renews its own sign-in: it rewrites its Keychain item.
    func renewLive(access: String) throws {
        try credentials(access: access).write(to: liveKeychainFile)
    }

    @discardableResult
    func saveAccount(_ account: ClaudeTestAccount, access: String, expiresAt: Date) throws -> UUID {
        try saveAccount(account, credentials: credentials(access: access, expiresAt: expiresAt))
    }

    @discardableResult
    func saveAccount(_ account: ClaudeTestAccount, credentials: Data) throws -> UUID {
        let signIn = try #require(ClaudeCodeSignInSnapshot(credentials: credentials, globalConfig: globalConfig(account)))
        return try store.add(signIn).id
    }

    func expireSavedSignIn(of id: UUID) throws {
        let saved = try store.savedSignIn(id)
        var object = try #require(try JSONSerialization.jsonObject(with: saved.itemData) as? [String: Any])
        var oauth = try #require(object["claudeAiOauth"] as? [String: Any])
        oauth["expiresAt"] = Int(now.addingTimeInterval(-60).timeIntervalSince1970 * 1_000)
        object["claudeAiOauth"] = oauth
        _ = items.save(try JSONSerialization.data(withJSONObject: object), for: id)
    }

    func savedAccessToken(of email: String) throws -> String? {
        let account = try #require(try store.accounts().first { $0.email == email })
        return Self.accessToken(in: try store.savedSignIn(account.id).itemData)
    }

    func liveAccessToken() throws -> String? {
        Self.accessToken(in: try Data(contentsOf: liveKeychainFile))
    }

    func liveFiles() throws -> [Data] {
        [try Data(contentsOf: liveKeychainFile), try Data(contentsOf: globalConfigFile)]
    }

    func throwawayFolders() throws -> [String] {
        let throwaway = root.appendingPathComponent("throwaway", isDirectory: true)
        guard FileManager.default.fileExists(atPath: throwaway.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: throwaway.path)
    }

    func remove() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    private static func accessToken(in data: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["claudeAiOauth"] as? [String: Any])?["accessToken"] as? String
    }
}

private final class FolderCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.withLock {
            count += 1
            return count
        }
    }
}
