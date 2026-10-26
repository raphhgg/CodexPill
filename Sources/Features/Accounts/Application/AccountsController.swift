import Foundation
import Observation
import OSLog

private let accountsControllerLogger = Logger(subsystem: "com.raphhgg.rusage", category: "AccountsController")

/// The one Codex account on this Mac: the sign-in in `auth.json`, its last reading, its resets, and replacing it with
/// another sign-in. rusage keeps no other Codex account.
@MainActor
@Observable
final class AccountsController {
    enum BackgroundRefreshOutcome: Equatable {
        case refreshed
        case failed(String)
    }

    private let authFile: CodexAuthFile
    private let accountStatusClient: CodexAccountStatusClient
    private let signInWorkflow: CodexSignInWorkflow
    private let resetCreditClient: CodexResetCreditClient
    private let operationState: AccountOperationState
    private let makeIdempotencyKey: () -> UUID
    private let postSignInRefreshDelay: Duration

    /// Nil while Codex is signed out on this Mac.
    private(set) var activeAccount: CodexAccount?
    private var pendingResetCreditKey: UUID?
    private(set) var isApplyingResetCredit = false

    init(
        authFile: CodexAuthFile,
        accountStatusClient: CodexAccountStatusClient,
        signInWorkflow: CodexSignInWorkflow,
        resetCreditClient: CodexResetCreditClient = UnavailableResetCreditClient(),
        operationState: AccountOperationState = AccountOperationState(),
        makeIdempotencyKey: @escaping () -> UUID = UUID.init,
        postSignInRefreshDelay: Duration = .seconds(2)
    ) {
        self.authFile = authFile
        self.accountStatusClient = accountStatusClient
        self.signInWorkflow = signInWorkflow
        self.resetCreditClient = resetCreditClient
        self.operationState = operationState
        self.makeIdempotencyKey = makeIdempotencyKey
        self.postSignInRefreshDelay = postSignInRefreshDelay
    }

    func load() {
        activeAccount = authFile.currentAccount()
    }

    /// Follows a sign-in Codex or the user changed outside rusage. The last reading stays while it is the same account.
    func refreshActiveAccount() {
        let fingerprint = authFile.currentFingerprint()
        guard fingerprint != activeAccount?.identity.snapshotFingerprint else { return }
        guard let current = authFile.currentAccount() else {
            activeAccount = nil
            return
        }
        // Codex rotates its tokens, which changes the file but not the account.
        if var same = activeAccount, same.isSameAccount(as: current) {
            same.identity = current.identity
            activeAccount = same
        } else {
            activeAccount = current
        }
    }

    /// Reads the signed-in account's limits from the Codex app-server.
    func refreshAccountData() async -> BackgroundRefreshOutcome {
        refreshActiveAccount()
        guard let accountBeforeRead = activeAccount else { return .failed("Codex is signed out.") }
        do {
            let remote = try await accountStatusClient.readCurrentAccountStatus()
            // A sign-in can land while the read awaits; its numbers would belong to the old account.
            guard activeAccount?.id == accountBeforeRead.id else { return .failed("The Codex sign-in changed.") }
            var account = accountBeforeRead
            account.applyRemoteMetadata(
                email: remote.email,
                planType: remote.planType,
                usage: remote.usage ?? account.usage,
                preferRateLimitPlan: remote.usage != nil
            )
            activeAccount = account
            return .refreshed
        } catch {
            accountsControllerLogger.log("Codex refresh skipped: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// Spends one reset credit on the signed-in account, then refreshes its limits. The attempt keeps its idempotency key
    /// until Codex answers, so a retry after a lost response cannot spend a second credit. A reset and a sign-in never
    /// overlap.
    func useResetCredit() async -> ResetCreditResult {
        guard !isBusy else { return .accountChangeInProgress }
        guard activeAccount != nil, !isApplyingResetCredit else { return .failed }
        isApplyingResetCredit = true
        defer { isApplyingResetCredit = false }
        let key = pendingResetCreditKey ?? makeIdempotencyKey()
        pendingResetCreditKey = key

        let outcome: CodexResetCreditOutcome
        do {
            outcome = try await resetCreditClient.consumeResetCredit(idempotencyKey: key)
        } catch {
            accountsControllerLogger.log("Reset credit not used: \(error.localizedDescription, privacy: .public)")
            return .failed
        }

        let result = ResetCreditResult(outcome)
        if result != .unconfirmed {
            pendingResetCreditKey = nil
        }
        accountsControllerLogger.log("Reset credit outcome: \(outcome.rawValue, privacy: .public)")
        if result == .reset || result == .unconfirmed {
            _ = await refreshAccountData()
        }
        return result
    }

    func startSignIn() async throws -> CodexSignInSession {
        guard !isBusy, !isApplyingResetCredit else { throw AccountsControllerError.operationAlreadyInProgress }
        operationState.begin(status: "Signing in to Codex...")
        do {
            return try await signInWorkflow.start()
        } catch {
            operationState.fail(error)
            throw error
        }
    }

    /// The account the browser sign-in returned. This Mac is unchanged until `use(_:)`.
    func completeSignIn(_ session: CodexSignInSession) async throws -> CodexSignedInAccount {
        do {
            let signedIn = try await signInWorkflow.complete(session)
            operationState.succeed()
            return signedIn
        } catch {
            if error as? CodexSignInWorkflowError == .accountAlreadyInUse {
                operationState.succeed()
            } else {
                operationState.fail(error)
            }
            throw error
        }
    }

    func cancelSignIn(_ session: CodexSignInSession) {
        signInWorkflow.cancel(session)
        operationState.succeed()
    }

    /// Makes `signedIn` the Codex account on this Mac and relaunches Codex. Nil when replacing `auth.json` failed.
    func use(_ signedIn: CodexSignedInAccount) async -> CodexRelaunch? {
        guard !isApplyingResetCredit else {
            operationState.fail(AccountsControllerError.resetCreditInProgress)
            return nil
        }
        operationState.begin(status: "Switching Codex account...")
        do {
            let relaunch = try await signInWorkflow.use(signedIn)
            activeAccount = authFile.currentAccount()
            operationState.succeed()
            if postSignInRefreshDelay > .zero {
                try? await Task.sleep(for: postSignInRefreshDelay)
            }
            _ = await refreshAccountData()
            return relaunch
        } catch {
            operationState.fail(error)
            return nil
        }
    }

    var pendingErrorMessage: String? {
        operationState.pendingErrorMessage
    }

    var statusMessage: String {
        operationState.statusMessage
    }

    var isBusy: Bool {
        operationState.isBusy
    }

    func consumePendingErrorMessage() -> String? {
        operationState.consumePendingErrorMessage()
    }
}

enum AccountsControllerError: LocalizedError, Equatable {
    case operationAlreadyInProgress
    case resetCreditInProgress

    var errorDescription: String? {
        switch self {
        case .operationAlreadyInProgress:
            "Another account operation is already in progress."
        case .resetCreditInProgress:
            "A reset is in progress. Try again when it finishes."
        }
    }
}
