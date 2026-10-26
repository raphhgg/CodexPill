import Foundation
import Testing

@testable import RUsage

@MainActor
struct AccountsControllerTests {
    @Test
    func theAccountIsTheOneAuthJSONSignsInTo() {
        let signedIn = makeController(authFile: makeCodexAuthFile(makeCodexAuthData(email: "alex@example.com")))
        let signedOut = makeController(authFile: makeCodexAuthFile())

        signedIn.load()
        signedOut.load()

        #expect(signedIn.activeAccount?.email == "alex@example.com")
        #expect(signedOut.activeAccount == nil)
    }

    @Test
    func aRefreshAppliesTheReading() async {
        let usage = makeUsage(planType: "pro")
        let controller = makeController(
            authFile: makeCodexAuthFile(makeCodexAuthData(email: "alex@example.com")),
            accountStatusClient: StubAccountStatusClient(status: CodexAccountStatus(email: "alex@example.com", planType: "pro", usage: usage))
        )
        controller.load()

        let outcome = await controller.refreshAccountData()

        #expect(outcome == .refreshed)
        #expect(controller.activeAccount?.usage == usage)
        #expect(controller.activeAccount?.effectivePlanType == "pro")
    }

    @Test
    func aFailedRefreshKeepsTheLastReadingAndQueuesNoError() async {
        let usage = makeUsage()
        let status = SequencedAccountStatusClient([.success(CodexAccountStatus(email: "alex@example.com", planType: nil, usage: usage)), .failure(TestFailure.refreshFailed)])
        let controller = makeController(authFile: makeCodexAuthFile(makeCodexAuthData(email: "alex@example.com")), accountStatusClient: status)
        controller.load()

        _ = await controller.refreshAccountData()
        let outcome = await controller.refreshAccountData()

        #expect(outcome == .failed(TestFailure.refreshFailed.localizedDescription))
        #expect(controller.activeAccount?.usage == usage)
        #expect(controller.pendingErrorMessage == nil)
    }

    @Test
    func rotatedTokensKeepTheAccountAndItsReading() async {
        let authFile = makeCodexAuthFile(makeCodexAuthData(email: "alex@example.com", refreshToken: "r1"))
        let usage = makeUsage()
        let controller = makeController(
            authFile: authFile,
            accountStatusClient: StubAccountStatusClient(status: CodexAccountStatus(email: "alex@example.com", planType: nil, usage: usage))
        )
        controller.load()
        _ = await controller.refreshAccountData()
        let id = controller.activeAccount?.id

        try? authFile.write(makeCodexAuthData(email: "alex@example.com", refreshToken: "r2"))
        controller.refreshActiveAccount()

        #expect(controller.activeAccount?.id == id)
        #expect(controller.activeAccount?.usage == usage)
    }

    @Test
    func anotherSignInMadeOutsideRusageReplacesTheAccountAndItsReading() async {
        let authFile = makeCodexAuthFile(makeCodexAuthData(email: "alex@example.com"))
        let controller = makeController(
            authFile: authFile,
            accountStatusClient: StubAccountStatusClient(status: CodexAccountStatus(email: "alex@example.com", planType: nil, usage: makeUsage()))
        )
        controller.load()
        _ = await controller.refreshAccountData()

        try? authFile.write(makeCodexAuthData(email: "sam@example.com", accountID: "acct-2", userID: "user-2"))
        controller.refreshActiveAccount()

        #expect(controller.activeAccount?.email == "sam@example.com")
        #expect(controller.activeAccount?.usage == nil)
    }

    @Test
    func aNewSignInReplacesAuthJSONOnlyWhenUsedAndRelaunchesCodex() async throws {
        let authFile = makeCodexAuthFile(makeCodexAuthData(email: "alex@example.com"))
        let newAuth = makeCodexAuthData(email: "sam@example.com", accountID: "acct-2", userID: "user-2")
        let codexApp = CodexAppProcessProbe()
        let controller = makeController(authFile: authFile, login: IsolatedCodexLoginProbe(authData: newAuth), codexApp: codexApp)
        controller.load()

        let session = try await controller.startSignIn()
        let signedIn = try await controller.completeSignIn(session)

        #expect(signedIn.account.email == "sam@example.com")
        #expect(controller.activeAccount?.email == "alex@example.com")
        #expect(codexApp.relaunchCount == 0)

        let relaunch = await controller.use(signedIn)

        #expect(relaunch == .relaunched)
        #expect(try authFile.read() == newAuth)
        #expect(controller.activeAccount?.email == "sam@example.com")
        #expect(codexApp.relaunchCount == 1)
        #expect(!controller.isBusy)
    }

    @Test
    func signingInToTheAccountAlreadyInUseChangesNothing() async throws {
        let auth = makeCodexAuthData(email: "alex@example.com")
        let authFile = makeCodexAuthFile(auth)
        let controller = makeController(authFile: authFile, login: IsolatedCodexLoginProbe(authData: makeCodexAuthData(email: "alex@example.com", refreshToken: "other")))
        controller.load()

        let session = try await controller.startSignIn()
        await #expect(throws: CodexSignInWorkflowError.accountAlreadyInUse) {
            try await controller.completeSignIn(session)
        }

        #expect(try authFile.read() == auth)
        #expect(controller.pendingErrorMessage == nil)
        #expect(!controller.isBusy)
    }

    @Test
    func aSignInMadeElsewhereDuringTheBrowserSignInIsNeverOverwritten() async throws {
        let authFile = makeCodexAuthFile(makeCodexAuthData(email: "alex@example.com"))
        let login = IsolatedCodexLoginProbe(authData: makeCodexAuthData(email: "sam@example.com", accountID: "acct-2", userID: "user-2"))
        let elsewhere = makeCodexAuthData(email: "kim@example.com", accountID: "acct-3", userID: "user-3")
        login.whileWaiting = { try? authFile.write(elsewhere) }
        let controller = makeController(authFile: authFile, login: login)
        controller.load()

        let session = try await controller.startSignIn()
        await #expect(throws: CodexSignInWorkflowError.liveAuthChanged) {
            try await controller.completeSignIn(session)
        }

        #expect(try authFile.read() == elsewhere)
    }

    @Test
    func aSecondSignInIsRefusedWhileOneRuns() async throws {
        let controller = makeController(authFile: makeCodexAuthFile(makeCodexAuthData(email: "alex@example.com")))
        controller.load()

        _ = try await controller.startSignIn()

        await #expect(throws: AccountsControllerError.operationAlreadyInProgress) {
            try await controller.startSignIn()
        }
        #expect(controller.isBusy)
    }

    @Test
    func signingOutRemovesAuthJSONAndRelaunchesCodex() async {
        let authFile = makeCodexAuthFile(makeCodexAuthData(email: "alex@example.com"))
        let codexApp = CodexAppProcessProbe()
        let controller = makeController(authFile: authFile, codexApp: codexApp)
        controller.load()

        let relaunch = await controller.signOut()

        #expect(relaunch == .relaunched)
        #expect(!FileManager.default.fileExists(atPath: authFile.url.path))
        #expect(controller.activeAccount == nil)
        #expect(codexApp.relaunchCount == 1)
        #expect(!controller.isBusy)
    }

    @Test
    func useResetCreditRefreshesLimitsAfterReset() async {
        var refreshedUsage = makeUsage()
        refreshedUsage.resetCredits = UsageResetCredits(availableCount: 1, credits: nil)
        let controller = makeController(
            authFile: makeCodexAuthFile(makeCodexAuthData(email: "alex@example.com")),
            accountStatusClient: StubAccountStatusClient(status: CodexAccountStatus(email: "alex@example.com", planType: "pro", usage: refreshedUsage)),
            resetCreditClient: ResetCreditClientProbe(results: [.success(.reset)])
        )
        controller.load()

        let result = await controller.useResetCredit()

        #expect(result == .reset)
        #expect(result.message == "Your Codex limits are reset.")
        #expect(controller.activeAccount?.usage?.resetCredits == UsageResetCredits(availableCount: 1, credits: nil))
    }

    @Test
    func useResetCreditRetriesWithTheSameKeyUntilCodexAnswers() async {
        let resetCredits = ResetCreditClientProbe(results: [
            .failure(TestFailure.refreshFailed),
            .success(.alreadyRedeemed),
            .success(.noCredit),
        ])
        let keys = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        ]
        var nextKey = keys.makeIterator()
        let controller = makeController(
            authFile: makeCodexAuthFile(makeCodexAuthData(email: "alex@example.com")),
            resetCreditClient: resetCredits,
            makeIdempotencyKey: { nextKey.next()! }
        )
        controller.load()

        let failed = await controller.useResetCredit()
        let retried = await controller.useResetCredit()
        let nextAttempt = await controller.useResetCredit()

        #expect(failed == .failed)
        #expect(retried == .reset)
        #expect(nextAttempt == .noCredit)
        #expect(await resetCredits.receivedKeys == [keys[0], keys[0], keys[1]])
    }

    @Test
    func aResetIsRefusedWhileASignInRuns() async throws {
        let controller = makeController(
            authFile: makeCodexAuthFile(makeCodexAuthData(email: "alex@example.com")),
            resetCreditClient: ResetCreditClientProbe(results: [.success(.reset)])
        )
        controller.load()
        _ = try await controller.startSignIn()

        #expect(await controller.useResetCredit() == .accountChangeInProgress)
    }

    private func makeController(
        authFile: CodexAuthFile,
        accountStatusClient: CodexAccountStatusClient = DisabledAccountStatusClient(),
        login: IsolatedCodexLoginProbe = IsolatedCodexLoginProbe(authData: Data()),
        codexApp: CodexAppProcessProbe = CodexAppProcessProbe(),
        resetCreditClient: CodexResetCreditClient = UnavailableResetCreditClient(),
        makeIdempotencyKey: @escaping () -> UUID = UUID.init
    ) -> AccountsController {
        AccountsController(
            authFile: authFile,
            accountStatusClient: accountStatusClient,
            signInWorkflow: CodexSignInWorkflow(authFile: authFile, isolatedLoginClient: login, codexAppProcessClient: codexApp),
            resetCreditClient: resetCreditClient,
            makeIdempotencyKey: makeIdempotencyKey,
            postSignInRefreshDelay: .zero
        )
    }
}

private enum TestFailure: LocalizedError {
    case refreshFailed

    var errorDescription: String? { "Refresh failed." }
}

private final class SequencedAccountStatusClient: CodexAccountStatusClient, @unchecked Sendable {
    private var results: [Result<CodexAccountStatus, Error>]

    init(_ results: [Result<CodexAccountStatus, Error>]) {
        self.results = results
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        try results.removeFirst().get()
    }
}

private actor ResetCreditClientProbe: CodexResetCreditClient {
    private var results: [Result<CodexResetCreditOutcome, Error>]
    private(set) var receivedKeys: [UUID] = []

    init(results: [Result<CodexResetCreditOutcome, Error>]) {
        self.results = results
    }

    func consumeResetCredit(idempotencyKey: UUID) async throws -> CodexResetCreditOutcome {
        receivedKeys.append(idempotencyKey)
        return try results.removeFirst().get()
    }
}
