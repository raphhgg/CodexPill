import Foundation
import Testing

@testable import Refill

struct CursorAccountsAddTests {
    private static let now = CursorAccessTokenFixtures.referenceDate
    private static let workToken = CursorAccessTokenFixtures.jwt(subject: "auth0|user_work", expiresAt: now.addingTimeInterval(86_400))
    private static let homeToken = CursorAccessTokenFixtures.jwt(subject: "auth0|user_home", expiresAt: now.addingTimeInterval(86_400))

    private static let work: [String: String] = [
        "cursorAuth/accessToken": workToken,
        "cursorAuth/refreshToken": "work-refresh-1",
        "cursorAuth/cachedEmail": "work@example.com",
        "cursorAuth/stripeMembershipType": "pro",
    ]

    private static let home: [String: String] = [
        "cursorAuth/accessToken": homeToken,
        "cursorAuth/refreshToken": "home-refresh-1",
        "cursorAuth/cachedEmail": "home@example.com",
    ]

    // MARK: - Add

    @Test
    func addingAnAccountSignsInInASeparateCursorWindowAndSavesThatSignIn() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        scenario.instances.behavior = .signsIn(Self.work)

        #expect(try await scenario.usage.addAccount() == true)

        let profile = try #require(scenario.instances.launchedProfiles.first)
        #expect(profile.deletingLastPathComponent().path == scenario.loginRoot.path)
        let saved = try scenario.store.load()
        #expect(saved.map(\.email) == ["work@example.com"])
        #expect(saved.first?.signIn.values[CursorSignIn.refreshTokenKey] == .text("work-refresh-1"))
        #expect(try scenario.liveRows()[CursorSignIn.accessTokenKey] == Self.homeToken)
        #expect(scenario.settings.isEnabled == true)
    }

    @Test
    func theSignInWaitsForTheEmailCursorWritesAfterTheTokens() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        scenario.instances.behavior = .signsIn(Self.work, emailLater: true)

        #expect(try await scenario.usage.addAccount() == true)

        #expect(try scenario.store.load().map(\.email) == ["work@example.com"])
    }

    @Test
    func onlyTheSignInWindowIsClosedAndItsProfileIsDeletedAfterwards() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        scenario.instances.behavior = .signsIn(Self.work)

        _ = try await scenario.usage.addAccount()

        #expect(scenario.instances.terminatedPIDs == [FakeCursorInstances.signInPID])
        #expect(scenario.instances.runningPIDs == [FakeCursorInstances.usersPID])
        #expect(scenario.instances.profileWasPresentAtQuit == [true])
        #expect(try scenario.leftoverProfiles() == [])
    }

    @Test
    func cancellingClosesTheWindowSavesNothingAndCleansUp() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        scenario.instances.behavior = .waits

        let add = Task { try await scenario.usage.addAccount() }
        while scenario.instances.launchedProfiles.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }
        add.cancel()

        #expect(try await add.value == false)
        #expect(try scenario.store.load() == [])
        #expect(scenario.instances.terminatedPIDs == [FakeCursorInstances.signInPID])
        #expect(scenario.instances.runningPIDs == [FakeCursorInstances.usersPID])
        #expect(try scenario.leftoverProfiles() == [])
    }

    @Test
    func aCancelledSignInWaitsForTheWindowToQuit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cq-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let started = folder.appendingPathComponent("started")
        let quit = folder.appendingPathComponent("quit")
        let standIn = folder.appendingPathComponent("cursor")
        try """
        #!/bin/sh
        trap 'sleep 0.3; touch "\(quit.path)"; exit 0' TERM
        touch "\(started.path)"
        while :; do sleep 0.05; done
        """.write(to: standIn, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: standIn.path)
        let login = CursorIsolatedLogin(
            launcher: ExecutableCursorInstanceLauncher(executable: standIn),
            root: folder.appendingPathComponent("p", isDirectory: true)
        )

        let signIn = Task { try await login.signIn() }
        while !FileManager.default.fileExists(atPath: started.path) {
            try await Task.sleep(for: .milliseconds(5))
        }
        signIn.cancel()

        await #expect(throws: CursorSignInError.cancelled) { try await signIn.value }
        #expect(FileManager.default.fileExists(atPath: quit.path))
    }

    @Test
    func aSignInThatNeverHappensTimesOutAndCleansUp() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home, timeout: .milliseconds(150))
        scenario.instances.behavior = .waits

        await #expect(throws: ProviderNotice(title: "Cursor sign-in timed out", detail: "Nothing was saved.")) {
            try await scenario.usage.addAccount()
        }
        #expect(try scenario.store.load() == [])
        #expect(scenario.instances.terminatedPIDs == [FakeCursorInstances.signInPID])
        #expect(try scenario.leftoverProfiles() == [])
    }

    @Test
    func quittingTheWindowBeforeSigningInSavesNothingAndCleansUp() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        scenario.instances.behavior = .quitsBeforeSignIn

        await #expect(throws: ProviderNotice(title: "Cursor sign-in didn't finish", detail: "Nothing was saved.")) {
            try await scenario.usage.addAccount()
        }
        #expect(try scenario.store.load() == [])
        #expect(try scenario.leftoverProfiles() == [])
    }

    @Test
    func whenCursorCannotOpenNothingIsLeftBehind() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        scenario.instances.behavior = .failsToLaunch

        await #expect(throws: ProviderNotice(title: "Couldn't open Cursor", detail: "Try again in a moment.")) {
            try await scenario.usage.addAccount()
        }
        #expect(scenario.instances.terminatedPIDs == [])
        #expect(try scenario.leftoverProfiles() == [])
    }

    @Test
    func aProfilePathTooLongForCursorsSocketIsRefusedBeforeOpeningCursor() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home, folderName: String(repeating: "x", count: 120))
        scenario.instances.behavior = .signsIn(Self.work)

        await #expect(throws: ProviderNotice(title: "Couldn't prepare the sign-in", detail: "Nothing was saved.")) {
            try await scenario.usage.addAccount()
        }
        #expect(scenario.instances.launchedProfiles == [])
    }

    @Test
    func withoutCursorInstalledAddingIsUnavailable() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        scenario.instances.isInstalled = false

        #expect(scenario.usage.signInAvailability == .notInstalled)
        await #expect(throws: ProviderNotice(title: "Install Cursor first", detail: nil)) {
            try await scenario.usage.addAccount()
        }
    }

    @Test
    func profilesLeftByAnEarlierRunAreDeleted() throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        try FileManager.default.createDirectory(
            at: scenario.loginRoot.appendingPathComponent("1a2b3c4d/User/globalStorage"),
            withIntermediateDirectories: true
        )

        scenario.login.removeLeftovers()

        #expect(try scenario.leftoverProfiles() == [])
    }

    // MARK: - Inactive accounts

    @Test
    func anInactiveAccountIsReadWithItsOwnSavedSignIn() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        let work = try scenario.save(Self.work)
        _ = try scenario.save(Self.home)
        scenario.web.response = .success(Data(CursorUsageFixture.proPlanWithCappedOnDemand.utf8))

        await scenario.usage.refreshInactiveAccount(work.id, now: Self.now)

        #expect(scenario.web.requestedUserIDs == ["user_work"])
        let accounts = try await scenario.usage.savedAccounts()
        let workUsage = try #require(accounts.first { $0.id == work.id }?.usage)
        #expect(workUsage.windows.map(\.usedPercent) == [82])
        #expect(accounts.first { $0.isActive }?.email == "home@example.com")
    }

    @Test
    func theActiveAccountIsNeverReadAsAnInactiveOne() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        let home = try scenario.save(Self.home)

        await scenario.usage.refreshInactiveAccount(home.id, now: Self.now)

        #expect(scenario.web.requestedUserIDs == [])
    }

    @Test
    func anExpiredSavedSignInIsNotRenewedAndKeepsItsLastLimits() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        var expired = Self.work
        expired[CursorSignIn.accessTokenKey] = CursorAccessTokenFixtures.jwt(subject: "auth0|user_work", expiresAt: Self.now.addingTimeInterval(-60))
        let work = try scenario.save(expired, usage: CursorUsageSnapshot(
            planName: "pro",
            includedUsagePercent: 40,
            onDemand: nil,
            billingCycle: nil,
            fetchedAt: Self.now.addingTimeInterval(-86_400)
        ))
        let before = try scenario.store.load()

        await scenario.usage.refreshInactiveAccount(work.id, now: Self.now)

        #expect(scenario.web.requestedUserIDs == [])
        #expect(try scenario.store.load() == before)
        #expect(try await scenario.usage.savedAccounts().first?.usage?.windows.map(\.usedPercent) == [40])
    }

    @Test
    func limitsReadWhileASwitchSavedRotatedTokensAreDroppedAndTheRotationKept() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        let work = try scenario.save(Self.work)
        var rotated = Self.work
        rotated[CursorSignIn.refreshTokenKey] = "work-refresh-2"
        let rotatedSignIn = try #require(CursorSignIn(values: rotated.mapValues(CursorStateValue.text)))
        scenario.web.response = .success(Data(CursorUsageFixture.proPlanWithCappedOnDemand.utf8))
        scenario.web.duringRequest = { [store = scenario.store] in
            var accounts = try! store.load()
            accounts[0].signIn = rotatedSignIn
            try! store.save(accounts)
        }

        await scenario.usage.refreshInactiveAccount(work.id, now: Self.now)

        let saved = try #require(try scenario.store.load().first)
        #expect(saved.signIn.values[CursorSignIn.refreshTokenKey] == .text("work-refresh-2"))
        #expect(saved.usage == nil)
    }

    // MARK: - Live account

    @Test @MainActor
    func aConnectedCursorsLiveAccountIsSavedOnceAndAgainWhenCursorSignsInToAnother() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        let runtime = ProviderUsageRuntime(connections: [scenario.usage], onChange: {})

        #expect(await runtime.perform(.connect, on: .cursor) == nil)
        await runtime.refreshIfDue(forcing: .cursor)
        #expect(try scenario.store.load().map(\.email) == ["home@example.com"])

        try scenario.harness.open()
        try scenario.harness.insertText(Self.work)
        scenario.harness.close()
        await runtime.refreshIfDue(forcing: .cursor)
        #expect(runtime.states.first?.accounts.map { "\($0.email ?? "") \($0.isActive)" } == ["home@example.com false", "work@example.com true"])
    }

    @Test @MainActor
    func aSavedLiveAccountKeepsItsSavedCopy() async throws {
        let scenario = try CursorAddScenario(liveSignIn: Self.home)
        var olderHome = Self.home
        olderHome[CursorSignIn.refreshTokenKey] = "home-refresh-0"
        let home = try scenario.save(olderHome)
        let runtime = ProviderUsageRuntime(connections: [scenario.usage], onChange: {})

        #expect(await runtime.perform(.connect, on: .cursor) == nil)

        let saved = try scenario.store.load()
        #expect(saved.map(\.id) == [home.id])
        #expect(saved.first?.signIn.values[CursorSignIn.refreshTokenKey] == .text("home-refresh-0"))
    }

    @Test @MainActor
    func switchingThroughTheRuntimeSavesTheTokensCursorRotatedFirst() async throws {
        var rotatedHome = Self.home
        rotatedHome[CursorSignIn.refreshTokenKey] = "home-refresh-2"
        let scenario = try CursorAddScenario(liveSignIn: rotatedHome)
        let work = try scenario.save(Self.work)
        _ = try scenario.save(Self.home)
        let runtime = ProviderUsageRuntime(connections: [scenario.usage], onChange: {})

        #expect(await runtime.perform(.switchAccount(work.id), on: .cursor) == nil)

        #expect(try scenario.liveRows()[CursorSignIn.accessTokenKey] == Self.workToken)
        let home = try #require(try scenario.store.load().first { $0.email == "home@example.com" })
        #expect(home.signIn.values[CursorSignIn.refreshTokenKey] == .text("home-refresh-2"))
    }
}

/// Cursor's live database signed in as one account, Refill's saved accounts, a separate-window sign-in with fake
/// Cursor instances, and a settable usage-summary response.
private final class CursorAddScenario: @unchecked Sendable {
    let harness: CursorStateDatabaseHarness
    let store = CursorAccountStoreHarness()
    let app = CursorAppProcessProbe()
    let instances = FakeCursorInstances()
    let web = RecordingCursorWebClient()
    let loginRoot: URL
    let login: CursorIsolatedLogin
    let settings: CursorUsageSettingsStore
    let usage: CursorUsage
    private let suiteName = "CursorAddScenario-\(UUID().uuidString)"

    init(liveSignIn: [String: String], timeout: Duration = .seconds(5), folderName: String? = nil) throws {
        harness = try CursorStateDatabaseHarness()
        try harness.create()
        try harness.insertText(liveSignIn)
        harness.close()

        // Short, like Refill's real folder: Cursor's socket path must fit in 103 bytes.
        loginRoot = FileManager.default.temporaryDirectory.appendingPathComponent("cs-\(UUID().uuidString.prefix(8))", isDirectory: true)
        var login = CursorIsolatedLogin(launcher: instances, root: loginRoot)
        login.timeout = timeout
        login.pollInterval = .milliseconds(5)
        login.settleTime = .seconds(2)
        if let folderName {
            login.newFolderName = { folderName }
        }
        self.login = login

        settings = CursorUsageSettingsStore(userDefaults: UserDefaults(suiteName: suiteName)!)
        usage = CursorUsage(
            settings: settings,
            client: CursorUsageClient(
                tokenSource: CursorStateDatabaseTokenSource(databaseURL: harness.databaseURL),
                webClient: web,
                now: { CursorAccessTokenFixtures.referenceDate }
            ),
            accounts: CursorAccounts(database: CursorStateDatabase(url: harness.databaseURL), store: store, app: app),
            login: login
        )
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: loginRoot)
    }

    func save(_ rows: [String: String], usage: CursorUsageSnapshot? = nil) throws -> CursorSavedAccount {
        let signIn = try #require(CursorSignIn(values: rows.mapValues(CursorStateValue.text)))
        let account = CursorSavedAccount(id: UUID(), signIn: signIn, usage: usage)
        try store.save(try store.load() + [account])
        return account
    }

    func liveRows() throws -> [String: String] {
        try CursorStateDatabase(url: harness.databaseURL).values(forKeys: CursorSignIn.keys).compactMapValues { value in
            guard case .text(let text) = value else { return nil }
            return text
        }
    }

    func leftoverProfiles() throws -> [String] {
        guard FileManager.default.fileExists(atPath: loginRoot.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: loginRoot.path)
    }
}

/// A usage-summary endpoint that records whose token each request carried.
final class RecordingCursorWebClient: CursorUsageWebClient, @unchecked Sendable {
    private let lock = NSLock()
    private var currentResponse: Result<Data, CursorUsageWebError> = .failure(.transport)
    private var userIDs: [String] = []
    var duringRequest: (@Sendable () -> Void)?

    var response: Result<Data, CursorUsageWebError> {
        get { lock.withLock { currentResponse } }
        set { lock.withLock { currentResponse = newValue } }
    }

    var requestedUserIDs: [String] { lock.withLock { userIDs } }

    func usageSummary(using token: CursorAccessToken) async throws -> Data {
        let response = lock.withLock {
            userIDs.append(token.userID)
            return currentResponse
        }
        duringRequest?()
        return try response.get()
    }
}
