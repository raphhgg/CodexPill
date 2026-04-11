import Foundation
import Observation
import OSLog

private let menuBarStoreLogger = Logger(subsystem: "com.raphhgg.codex-switchboard", category: "MenuBarStore")

extension Notification.Name {
    static let codexSwitchboardStoreDidChange = Notification.Name("CodexSwitchboardStoreDidChange")
}

@MainActor
@Observable
final class MenuBarStore {
    private let repository: AccountRepository
    private let authService: CodexAuthSnapshotService
    private let appServerClient: CodexAppServerClient
    private let activeAccountResolver: ActiveAccountResolver
    private let switchAccountWorkflow: SwitchAccountWorkflow
    private let saveCurrentAccountWorkflow: SaveCurrentAccountWorkflow
    private let signInAnotherWorkflow: SignInAnotherWorkflow

    private(set) var accounts: [CodexAccount] = []
    private(set) var activeAccountID: UUID?
    private var pendingSignedInAccountName: String?
    private(set) var pendingErrorMessage: String?
    var statusMessage = "Ready"
    var isBusy = false

    init(
        repository: AccountRepository,
        authService: CodexAuthSnapshotService,
        appController: CodexAppController,
        appServerClient: CodexAppServerClient
    ) {
        self.repository = repository
        self.authService = authService
        self.appServerClient = appServerClient
        self.activeAccountResolver = ActiveAccountResolver(authService: authService)
        self.switchAccountWorkflow = SwitchAccountWorkflow(
            authService: authService,
            repository: repository,
            appController: appController
        )
        self.saveCurrentAccountWorkflow = SaveCurrentAccountWorkflow(
            appServerClient: appServerClient,
            authService: authService,
            repository: repository
        )
        self.signInAnotherWorkflow = SignInAnotherWorkflow(
            authService: authService,
            appController: appController,
            appServerClient: appServerClient,
            repository: repository,
            activeAccountResolver: self.activeAccountResolver
        )
    }

    func load() {
        do {
            try repository.bootstrapStorage()
            let loadedAccounts = try repository.loadAccounts()
            let reconciledAccounts = authService.reconcileStoredAccountIdentities(loadedAccounts)
            accounts = reconciledAccounts
            if reconciledAccounts != loadedAccounts {
                try repository.saveAccounts(reconciledAccounts)
            }
            refreshActiveAccount()
            statusMessage = "Loaded \(accounts.count) account(s)"
            menuBarStoreLogger.log("Loaded \(self.accounts.count, privacy: .public) saved account(s)")
        } catch {
            statusMessage = "Ready"
            pendingErrorMessage = error.localizedDescription
            menuBarStoreLogger.error("Failed to load store: \(error.localizedDescription, privacy: .public)")
        }
        stateDidChange()
    }

    func saveCurrentAccountSnapshot(named customName: String?) async {
        await perform("Saving current Codex auth...") {
            let result = try await saveCurrentAccountWorkflow.run(
                customName: customName,
                existingAccounts: accounts
            )
            if let index = accounts.firstIndex(where: { $0.id == result.savedAccount.id }) {
                accounts[index] = result.savedAccount
            } else {
                accounts.append(result.savedAccount)
            }
            accounts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            activeAccountID = result.activeAccountID
        }
    }

    func completePendingSignedInAccountIfNeeded() async {
        guard let pendingSignedInAccountName else { return }
        guard activeAccountID == nil else {
            self.pendingSignedInAccountName = nil
            return
        }

        await perform("Saving signed-in account...") {
            guard let result = try await signInAnotherWorkflow.completePendingSignIn(
                pendingAccountName: pendingSignedInAccountName,
                existingAccounts: accounts
            ) else {
                return
            }
            accounts.append(result.savedAccount)
            accounts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            activeAccountID = result.activeAccountID
            self.pendingSignedInAccountName = nil
        }
    }

    func switchToAccount(_ account: CodexAccount) async {
        await perform("Switching to \(account.name)...") {
            activeAccountID = try await switchAccountWorkflow.run(
                account: account,
                accounts: accounts
            )
        }
    }

    func refreshAccountData(for account: CodexAccount) async {
        await perform("Refreshing account data for \(account.name)...") {
            let remote = try await appServerClient.readCurrentAccountStatus()
            let matchOutcome = activeAccountResolver.resolve(
                accounts: accounts,
                liveRemoteIdentity: remote.remoteIdentity
            )

            guard let matchedAccountID = matchOutcome.matchedAccountID else {
                throw MenuBarStoreError.refreshTargetResolutionFailed(matchOutcome)
            }

            guard let matchedAccount = accounts.first(where: { $0.id == matchedAccountID }) else {
                throw MenuBarStoreError.refreshTargetMissing
            }

            mutateAccount(matchedAccount) { stored in
                stored.applyRemoteMetadata(
                    email: remote.email,
                    planType: remote.planType,
                    rateLimits: remote.rateLimits
                )
            }
        }
    }

    func startSignInAnotherAccountFlow(named pendingAccountName: String?) async {
        menuBarStoreLogger.log("Starting sign-in-another flow")
        await perform("Preparing Codex sign-in...") {
            let result = try signInAnotherWorkflow.prepare(named: pendingAccountName)
            pendingSignedInAccountName = result.pendingAccountName
            activeAccountID = nil
            stateDidChange()
            try await signInAnotherWorkflow.relaunchCodex()
            menuBarStoreLogger.log("Sign-in-another relaunch finished")
        }
    }

    func refreshActiveAccount() {
        activeAccountID = activeAccountResolver.resolveActiveAccountID(accounts: accounts)
    }

    func isActive(_ account: CodexAccount) -> Bool {
        activeAccountID == account.id
    }

    var activeAccount: CodexAccount? {
        accounts.first(where: { $0.id == activeAccountID })
    }

    var inactiveAccounts: [CodexAccount] {
        accounts.filter { $0.id != activeAccountID }
    }

    var sortedInactiveAccounts: [CodexAccount] {
        inactiveAccounts.sorted(by: compareInactiveAccounts)
    }

    private func perform(_ status: String, operation: () async throws -> Void) async {
        menuBarStoreLogger.log("Beginning operation with status: \(status, privacy: .public)")
        isBusy = true
        statusMessage = status
        stateDidChange()
        do {
            try await operation()
            statusMessage = "Done"
            menuBarStoreLogger.log("Operation completed successfully for status: \(status, privacy: .public)")
        } catch {
            statusMessage = "Ready"
            pendingErrorMessage = error.localizedDescription
            menuBarStoreLogger.error("Operation failed for status \(status, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        isBusy = false
        stateDidChange()
    }

    func consumePendingErrorMessage() -> String? {
        let message = pendingErrorMessage
        pendingErrorMessage = nil
        return message
    }

    private func mutateAccount(_ account: CodexAccount, mutation: (inout CodexAccount) -> Void) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        mutation(&accounts[index])
        accounts[index].updatedAt = .now
        try? repository.saveAccounts(accounts)
        stateDidChange()
    }

    private func stateDidChange() {
        NotificationCenter.default.post(name: .codexSwitchboardStoreDidChange, object: self)
    }

    private func compareInactiveAccounts(_ lhs: CodexAccount, _ rhs: CodexAccount) -> Bool {
        let leftKey = availabilitySortKey(for: lhs)
        let rightKey = availabilitySortKey(for: rhs)

        if leftKey.weeklyConstraintRank != rightKey.weeklyConstraintRank {
            return leftKey.weeklyConstraintRank < rightKey.weeklyConstraintRank
        }

        if leftKey.sessionReadyRank != rightKey.sessionReadyRank {
            return leftKey.sessionReadyRank < rightKey.sessionReadyRank
        }

        if leftKey.effectiveAvailableAt != rightKey.effectiveAvailableAt {
            return leftKey.effectiveAvailableAt < rightKey.effectiveAvailableAt
        }

        if leftKey.weeklyUsedPercent != rightKey.weeklyUsedPercent {
            return leftKey.weeklyUsedPercent < rightKey.weeklyUsedPercent
        }

        if leftKey.sessionUsedPercent != rightKey.sessionUsedPercent {
            return leftKey.sessionUsedPercent < rightKey.sessionUsedPercent
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func resolvedAccountName(_ customName: String?, fallbackEmail: String?) -> String {
        let trimmedCustomName = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedCustomName.isEmpty {
            return trimmedCustomName
        }

        let trimmedEmail = fallbackEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedEmail.isEmpty {
            return trimmedEmail
        }

        return "Codex Account"
    }

    private func availabilitySortKey(for account: CodexAccount) -> AvailabilitySortKey {
        let now = Date()
        let sessionWindow = account.rateLimits?.primary
        let weeklyWindow = account.rateLimits?.secondary
        let sessionUsedPercent = sessionWindow?.usedPercent ?? 100
        let weeklyUsedPercent = weeklyWindow?.usedPercent ?? 100

        let weeklyConstraintRank: Int
        switch weeklyUsedPercent {
        case ..<85:
            weeklyConstraintRank = 0
        case 85..<95:
            weeklyConstraintRank = 1
        default:
            weeklyConstraintRank = 2
        }

        let sessionReadyRank: Int
        switch sessionUsedPercent {
        case ..<10:
            sessionReadyRank = 0
        case 10..<40:
            sessionReadyRank = 1
        default:
            sessionReadyRank = 2
        }

        let sessionAvailableAt: Date = sessionReadyRank == 0 ? now : (sessionWindow?.resetsAt ?? .distantFuture)
        let weeklyAvailableAt: Date = weeklyConstraintRank < 2 ? now : (weeklyWindow?.resetsAt ?? .distantFuture)

        return AvailabilitySortKey(
            weeklyConstraintRank: weeklyConstraintRank,
            sessionReadyRank: sessionReadyRank,
            effectiveAvailableAt: max(sessionAvailableAt, weeklyAvailableAt),
            weeklyUsedPercent: weeklyUsedPercent,
            sessionUsedPercent: sessionUsedPercent
        )
    }
}

private enum MenuBarStoreError: LocalizedError {
    case refreshTargetResolutionFailed(CodexAccountMatchOutcome)
    case refreshTargetMissing

    var errorDescription: String? {
        switch self {
        case .refreshTargetResolutionFailed(.ambiguousSnapshotFingerprint):
            "Could not refresh the active account because more than one saved account matches the current auth snapshot."
        case .refreshTargetResolutionFailed(.ambiguousRemoteIdentity):
            "Could not refresh the active account because more than one saved account matches the current Codex account identity."
        case .refreshTargetResolutionFailed(.noMatch):
            "Could not refresh the active account because the current Codex account does not match any saved account."
        case .refreshTargetResolutionFailed(.exactSnapshot), .refreshTargetResolutionFailed(.uniqueRemoteIdentity):
            "Could not refresh the active account."
        case .refreshTargetMissing:
            "Could not refresh the active account because the matched saved account is missing."
        }
    }
}

private struct AvailabilitySortKey {
    let weeklyConstraintRank: Int
    let sessionReadyRank: Int
    let effectiveAvailableAt: Date
    let weeklyUsedPercent: Int
    let sessionUsedPercent: Int
}
