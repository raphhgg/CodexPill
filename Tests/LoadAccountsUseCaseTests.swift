import Foundation
import Testing

@testable import CodexPill

struct LoadAccountsUseCaseTests {
    @Test
    func runBootstrapsLoadsReconcilesPersistsAndResolvesActiveAccount() throws {
        let saved = makeAccount(name: "Work", fingerprint: "live")
        let reconciled = makeAccount(
            id: saved.id,
            name: saved.name,
            fingerprint: "live",
            email: "work@example.com"
        )

        let repository = LoadingRepositorySpy(accountsToLoad: [saved])
        let auth = ReconcileSpy(reconciledAccounts: [reconciled])
        let resolver = ActiveAccountResolver(authService: CurrentFingerprintStub(fingerprint: "live", stableAccountID: nil))
        let useCase = LoadAccountsUseCase(
            repository: repository,
            authService: auth,
            activeAccountResolver: resolver
        )

        let result = try useCase.run()

        #expect(repository.bootstrapCount == 1)
        #expect(repository.loadCount == 1)
        #expect(auth.inputAccounts == [saved])
        #expect(repository.savedAccounts == [reconciled])
        #expect(result.accounts == [reconciled])
        #expect(result.activeAccountID == reconciled.id)
    }

    @Test
    func runSkipsSaveWhenReconciliationDoesNotChangeAccounts() throws {
        let saved = makeAccount(name: "Work", fingerprint: "live")
        let repository = LoadingRepositorySpy(accountsToLoad: [saved])
        let auth = ReconcileSpy(reconciledAccounts: [saved])
        let resolver = ActiveAccountResolver(authService: CurrentFingerprintStub(fingerprint: nil, stableAccountID: nil))
        let useCase = LoadAccountsUseCase(
            repository: repository,
            authService: auth,
            activeAccountResolver: resolver
        )

        let result = try useCase.run()

        #expect(repository.savedAccounts == nil)
        #expect(result.accounts == [saved])
        #expect(result.activeAccountID == nil)
    }

    @Test
    func runPersistsBackfilledStableAccountIDForExistingSnapshot() throws {
        let id = UUID()
        let saved = CodexAccount(
            id: id,
            name: "Work",
            snapshotFileName: "\(id.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "work@example.com",
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: nil,
                snapshotFingerprint: "legacy-fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "work@example.com")
            )
        )
        let reconciled = CodexAccount(
            id: id,
            name: "Work",
            snapshotFileName: "\(id.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "work@example.com",
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: "acct-123",
                snapshotFingerprint: "legacy-fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "work@example.com")
            )
        )

        let repository = LoadingRepositorySpy(accountsToLoad: [saved])
        let auth = ReconcileSpy(reconciledAccounts: [reconciled])
        let resolver = ActiveAccountResolver(authService: CurrentFingerprintStub(fingerprint: nil, stableAccountID: "acct-123"))
        let useCase = LoadAccountsUseCase(
            repository: repository,
            authService: auth,
            activeAccountResolver: resolver
        )

        let result = try useCase.run()

        #expect(repository.savedAccounts == [reconciled])
        #expect(result.activeAccountID == id)
    }

    private func makeAccount(
        id: UUID = UUID(),
        name: String,
        fingerprint: String,
        email: String? = nil
    ) -> CodexAccount {
        CodexAccount(
            id: id,
            name: name,
            snapshotFileName: "\(id.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: email,
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: nil,
                snapshotFingerprint: fingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: email)
            )
        )
    }
}

private final class LoadingRepositorySpy: AccountCatalogLoading {
    let accountsToLoad: [CodexAccount]
    var bootstrapCount = 0
    var loadCount = 0
    var savedAccounts: [CodexAccount]?

    init(accountsToLoad: [CodexAccount]) {
        self.accountsToLoad = accountsToLoad
    }

    func bootstrapStorage() throws {
        bootstrapCount += 1
    }

    func loadAccounts() throws -> [CodexAccount] {
        loadCount += 1
        return accountsToLoad
    }

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}

private final class ReconcileSpy: StoredAccountReconciling {
    let reconciledAccounts: [CodexAccount]
    var inputAccounts: [CodexAccount]?

    init(reconciledAccounts: [CodexAccount]) {
        self.reconciledAccounts = reconciledAccounts
    }

    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        inputAccounts = accounts
        return reconciledAccounts
    }
}

private struct CurrentFingerprintStub: CodexAuthFingerprintReading {
    let fingerprint: String?
    let stableAccountID: String?

    func currentAuthFingerprint() -> String? {
        fingerprint
    }

    func currentStableAccountID() -> String? {
        stableAccountID
    }
}
