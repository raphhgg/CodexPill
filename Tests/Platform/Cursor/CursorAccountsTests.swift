import Foundation
import SQLite3
import Testing

@testable import CodexPill

struct CursorAccountsTests {
    private static let workToken = CursorAccessTokenFixtures.jwt(subject: "auth0|user_work", expiresAt: CursorAccessTokenFixtures.referenceDate)
    private static let homeToken = CursorAccessTokenFixtures.jwt(subject: "google-oauth2|user_home", expiresAt: CursorAccessTokenFixtures.referenceDate)

    private static let work: [String: String] = [
        "cursorAuth/accessToken": workToken,
        "cursorAuth/refreshToken": "work-refresh-1",
        "cursorAuth/cachedEmail": "work@example.com",
        "cursorAuth/cachedScopedProfile": #"{"scope":"work"}"#,
        "cursorAuth/cachedSignUpType": "Auth_0",
        "cursorAuth/stripeMembershipAuthId": "auth0|user_work",
        "cursorAuth/stripeMembershipType": "pro",
        "cursorAuth/stripeSubscriptionStatus": "active",
    ]

    // A free account has no subscription status row.
    private static let home: [String: String] = [
        "cursorAuth/accessToken": homeToken,
        "cursorAuth/refreshToken": "home-refresh-1",
        "cursorAuth/cachedEmail": "home@example.com",
        "cursorAuth/cachedScopedProfile": #"{"scope":"home"}"#,
        "cursorAuth/cachedSignUpType": "Google",
        "cursorAuth/stripeMembershipAuthId": "google-oauth2|user_home",
        "cursorAuth/stripeMembershipType": "free",
    ]

    private static let unrelatedRows: [String: String] = [
        "workbench.panel.width": "320",
        "glass.lastSignedInAuthId": "auth0|user_work",
    ]

    // MARK: - Capture

    @Test
    func captureSavesCurrentSignInWithPlanAndEmail() throws {
        let scenario = try Scenario(signedInAs: Self.work)

        let account = try scenario.accounts.captureCurrent(named: "Work")

        #expect(account.name == "Work")
        #expect(account.plan == "pro")
        #expect(account.email == "work@example.com")
        #expect(account.userID == "user_work")
        #expect(try scenario.store.load() == [account])
        #expect(account.signIn.values.count == CursorSignIn.keys.count)
    }

    @Test
    func captureNeverOpensDatabaseForWriting() throws {
        let scenario = try Scenario(signedInAs: Self.work)
        let before = try Data(contentsOf: scenario.harness.databaseURL)

        try scenario.accounts.captureCurrent(named: "Work")

        #expect(try Data(contentsOf: scenario.harness.databaseURL) == before)
        let cursorDirectory = scenario.harness.databaseURL.deletingLastPathComponent().path
        #expect(try FileManager.default.contentsOfDirectory(atPath: cursorDirectory) == ["state.vscdb"])
    }

    @Test
    func captureTwiceRefreshesTheSavedAccount() throws {
        let scenario = try Scenario(signedInAs: Self.work)
        let first = try scenario.accounts.captureCurrent(named: "Work")
        try scenario.harness.open()
        try scenario.harness.insertText("work-refresh-2", key: CursorSignIn.refreshTokenKey)
        scenario.harness.close()

        let second = try scenario.accounts.captureCurrent(named: "Day job")

        #expect(second.id == first.id)
        #expect(try scenario.store.load().map(\.name) == ["Day job"])
        #expect(try scenario.store.load().first?.signIn.values[CursorSignIn.refreshTokenKey] == .text("work-refresh-2"))
    }

    @Test
    func captureWhenSignedOutThrows() throws {
        let scenario = try Scenario(signedInAs: [:])

        #expect(throws: CursorAccountsError.signedOut) {
            try scenario.accounts.captureCurrent(named: "Work")
        }
        #expect(try scenario.store.load().isEmpty)
    }

    @Test
    func captureWithoutCursorThrows() throws {
        let scenario = try Scenario(signedInAs: nil)

        #expect(throws: CursorAccountsError.cursorNotInstalled) {
            try scenario.accounts.captureCurrent(named: "Work")
        }
    }

    // MARK: - Activate

    @Test
    func activateWritesOnlySignInRowsAndRemovesRowsTheTargetLacks() async throws {
        let scenario = try Scenario(signedInAs: Self.home)
        try scenario.accounts.captureCurrent(named: "Home")
        let work = try scenario.saveAccount(Self.work, named: "Work")

        try await scenario.accounts.activate(work.id)

        try scenario.harness.open()
        #expect(try scenario.harness.itemTable() == Self.work.merging(Self.unrelatedRows) { current, _ in current })
        #expect(try scenario.harness.diskKV() == ["composerData:1": "conversation"])
        #expect(try scenario.accounts.activeAccountID() == work.id)

        let home = try scenario.store.load().first { $0.name == "Home" }
        try await scenario.accounts.activate(try #require(home).id)

        #expect(try scenario.harness.itemTable()["cursorAuth/stripeSubscriptionStatus"] == nil)
        #expect(try scenario.harness.itemTable()[CursorSignIn.accessTokenKey] == Self.homeToken)
    }

    @Test
    func activateQuitsCursorBeforeWritingAndOpensItAfter() async throws {
        let scenario = try Scenario(signedInAs: Self.home)
        let work = try scenario.saveAccount(Self.work, named: "Work")
        scenario.app.onQuit = {
            // While Cursor runs, the database still holds the outgoing sign-in.
            let tokenWhileRunning = try scenario.harness.itemTableReadOnly()[CursorSignIn.accessTokenKey]
            #expect(tokenWhileRunning == Self.homeToken)
        }

        try await scenario.accounts.activate(work.id)

        #expect(scenario.app.events == [.quit, .open])
    }

    @Test
    func activateKeepsTokensCursorRotatedBeforeQuitting() async throws {
        let scenario = try Scenario(signedInAs: Self.home)
        let home = try scenario.accounts.captureCurrent(named: "Home")
        let work = try scenario.saveAccount(Self.work, named: "Work")
        scenario.app.onQuit = {
            // Cursor refreshed its session while running and saves the new token as it quits.
            try scenario.harness.open()
            try scenario.harness.insertText("home-refresh-2", key: CursorSignIn.refreshTokenKey)
            scenario.harness.close()
        }

        try await scenario.accounts.activate(work.id)

        let savedHome = try #require(try scenario.store.load().first { $0.id == home.id })
        #expect(savedHome.signIn.values[CursorSignIn.refreshTokenKey] == .text("home-refresh-2"))
    }

    @Test
    func activateSavesAnUnsavedOutgoingSignIn() async throws {
        let scenario = try Scenario(signedInAs: Self.home)
        let work = try scenario.saveAccount(Self.work, named: "Work")

        try await scenario.accounts.activate(work.id)

        let saved = try scenario.store.load()
        #expect(saved.map(\.name) == ["Work", "home@example.com"])
        #expect(saved.last?.userID == "user_home")
    }

    @Test
    func activateFoldsCursorsWALIntoTheDatabaseFile() async throws {
        let scenario = try Scenario(signedInAs: Self.home, walMode: true)
        let work = try scenario.saveAccount(Self.work, named: "Work")

        try await scenario.accounts.activate(work.id)

        #expect((scenario.harness.fileSize(suffix: "-wal") ?? 0) == 0)
        // An immutable open ignores the WAL, so this reads only what is in the database file itself.
        let immutable = CursorStateDatabaseTokenSource(databaseURL: scenario.harness.databaseURL)
        try? FileManager.default.removeItem(atPath: scenario.harness.databaseURL.path + "-wal")
        try? FileManager.default.removeItem(atPath: scenario.harness.databaseURL.path + "-shm")
        guard case .token(let token) = try immutable.lookup() else {
            Issue.record("Expected the work token in the database file")
            return
        }
        #expect(token.userID == "user_work")
    }

    @Test
    func activateWhenCursorDoesNotQuitChangesNothing() async throws {
        let scenario = try Scenario(signedInAs: Self.home)
        let work = try scenario.saveAccount(Self.work, named: "Work")
        let before = try Data(contentsOf: scenario.harness.databaseURL)
        scenario.app.quitError = CursorAppProcessClientError.didNotQuit

        await #expect(throws: CursorAppProcessClientError.didNotQuit) {
            try await scenario.accounts.activate(work.id)
        }

        #expect(try Data(contentsOf: scenario.harness.databaseURL) == before)
        #expect(scenario.app.events == [.quit])
        #expect(try scenario.store.load().map(\.name) == ["Work"])
    }

    @Test
    func activateWhileAnotherProcessHoldsTheDatabaseWritesNothingAndReopensCursor() async throws {
        let scenario = try Scenario(signedInAs: Self.home, walMode: true)
        let work = try scenario.saveAccount(Self.work, named: "Work")
        // A Cursor helper still has the database open after the app quit.
        scenario.app.onQuit = nil
        try scenario.harness.holdWriteLock()

        await #expect(throws: CursorStateDatabaseError.busy) {
            try await scenario.accounts.activate(work.id)
        }

        scenario.harness.close()
        #expect(try scenario.harness.itemTableReadOnly()[CursorSignIn.accessTokenKey] == Self.homeToken)
        #expect(scenario.app.events == [.quit, .open])
    }

    @Test
    func activateOnACorruptedDatabaseLeavesItUntouchedAndReopensCursor() async throws {
        let scenario = try Scenario(signedInAs: nil)
        let work = try scenario.saveAccount(Self.work, named: "Work")
        let garbage = Data(repeating: 0x5A, count: 8192)
        try garbage.write(to: scenario.harness.databaseURL)

        await #expect(throws: CursorStateDatabaseError.self) {
            try await scenario.accounts.activate(work.id)
        }

        #expect(try Data(contentsOf: scenario.harness.databaseURL) == garbage)
        #expect(scenario.app.events == [.quit, .open])
    }

    @Test
    func activateTheActiveAccountOnlyReopensCursor() async throws {
        let scenario = try Scenario(signedInAs: Self.work)
        let work = try scenario.accounts.captureCurrent(named: "Work")
        let before = try Data(contentsOf: scenario.harness.databaseURL)

        try await scenario.accounts.activate(work.id)

        #expect(try Data(contentsOf: scenario.harness.databaseURL) == before)
        #expect(scenario.app.events == [.quit, .open])
    }

    @Test
    func activateUnknownAccountThrowsWithoutQuittingCursor() async throws {
        let scenario = try Scenario(signedInAs: Self.home)

        await #expect(throws: CursorAccountsError.accountNotFound) {
            try await scenario.accounts.activate(UUID())
        }
        #expect(scenario.app.events.isEmpty)
    }

    // MARK: - Saved accounts

    @Test
    func renameAndRemoveChangeOnlyCodexPillsList() throws {
        let scenario = try Scenario(signedInAs: Self.work)
        let work = try scenario.accounts.captureCurrent(named: "Work")
        let before = try Data(contentsOf: scenario.harness.databaseURL)

        try scenario.accounts.rename(work.id, to: "Client")
        #expect(try scenario.accounts.savedAccounts().map(\.name) == ["Client"])

        try scenario.accounts.remove(work.id)
        #expect(try scenario.accounts.savedAccounts().isEmpty)
        #expect(try scenario.accounts.activeAccountID() == nil)
        #expect(try Data(contentsOf: scenario.harness.databaseURL) == before)
    }

    @Test
    func keychainPayloadRoundTripsAndSignInPrintsRedacted() throws {
        let signIn = try #require(CursorSignIn(values: Self.work.mapValues(CursorStateValue.text)))
        let account = CursorSavedAccount(id: UUID(), name: "Work", signIn: signIn)

        let decoded = try SystemCursorAccountKeychain.decode(SystemCursorAccountKeychain.encode([account]))

        #expect(decoded == [account])
        #expect(String(describing: signIn) == "CursorSignIn(redacted)")
        #expect(!String(describing: account).contains("work-refresh-1"))
        #expect(!String(reflecting: account).contains("work@example.com"))
    }

    @Test
    func signInIgnoresRowsOutsideTheSignInKeys() throws {
        var values = Self.work.mapValues(CursorStateValue.text)
        values["workbench.panel.width"] = .text("320")

        let signIn = try #require(CursorSignIn(values: values))

        #expect(Set(signIn.values.keys) == Set(CursorSignIn.keys))
    }
}

/// A temporary isolated root with Cursor's database at `<root>/Cursor/state.vscdb`, the layout
/// `CODEXPILL_ISOLATED_APP_SUPPORT_DIR` uses.
private final class Scenario: @unchecked Sendable {
    let harness: CursorStateDatabaseHarness
    let store = CursorAccountStoreHarness()
    let app = CursorAppProcessProbe()
    let accounts: CursorAccounts

    /// `signedInAs: nil` leaves Cursor uninstalled. An empty dictionary is a signed-out Cursor.
    init(signedInAs signIn: [String: String]?, walMode: Bool = false) throws {
        harness = try CursorStateDatabaseHarness(databasePath: "Cursor/state.vscdb")
        var database = CursorStateDatabase(url: CursorStateDatabase.isolatedURL(root: harness.directoryURL))
        database.writeBusyTimeout = .milliseconds(100)
        accounts = CursorAccounts(database: database, store: store, app: app)

        guard let signIn else { return }
        try harness.create(walMode: walMode)
        try harness.insertText(signIn)
        try harness.insertText([
            "workbench.panel.width": "320",
            "glass.lastSignedInAuthId": "auth0|user_work",
        ])
        try harness.insertDiskKV("conversation", key: "composerData:1")
        if walMode {
            // Cursor is running: its connection stays open and the rows above sit in the WAL.
            app.onQuit = { [harness] in harness.close() }
        } else {
            harness.close()
        }
    }

    func saveAccount(_ values: [String: String], named name: String) throws -> CursorSavedAccount {
        let signIn = try #require(CursorSignIn(values: values.mapValues(CursorStateValue.text)))
        let account = CursorSavedAccount(id: UUID(), name: name, signIn: signIn)
        try store.save(try store.load() + [account])
        return account
    }
}

private extension CursorStateDatabaseHarness {
    func itemTableReadOnly() throws -> [String: String] {
        let values = try CursorStateDatabase(url: databaseURL).values(forKeys: CursorSignIn.keys)
        return values.compactMapValues { value in
            guard case .text(let text) = value else { return nil }
            return text
        }
    }
}

final class CursorAccountStoreHarness: CursorAccountStore, @unchecked Sendable {
    private let lock = NSLock()
    private var accounts: [CursorSavedAccount] = []

    func load() throws -> [CursorSavedAccount] {
        lock.withLock { accounts }
    }

    func save(_ accounts: [CursorSavedAccount]) throws {
        lock.withLock { self.accounts = accounts }
    }
}

final class CursorAppProcessProbe: CursorAppProcessClient, @unchecked Sendable {
    enum Event: Equatable {
        case quit
        case open
    }

    private let lock = NSLock()
    private var recorded: [Event] = []
    var quitError: (any Error)?
    var onQuit: (() throws -> Void)?

    var events: [Event] { lock.withLock { recorded } }
    var isRunning: Bool { true }

    func quit() async throws {
        lock.withLock { recorded.append(.quit) }
        try onQuit?()
        if let quitError { throw quitError }
    }

    func open() async throws {
        lock.withLock { recorded.append(.open) }
    }
}
