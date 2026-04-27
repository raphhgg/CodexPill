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

        let repository = LoadingAccountCatalogProbe(accountsToLoad: [saved])
        let auth = IdentityReconcilerProbe(reconciledAccounts: [reconciled])
        let resolver = SavedAccountIdentityResolver(
            liveIdentitySource: CurrentIdentityFixture(fingerprint: "live", stableAccountID: nil),
            storedAccountReconciler: auth
        )
        let useCase = LoadAccountsUseCase(
            repository: repository,
            identityResolver: resolver
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
        let repository = LoadingAccountCatalogProbe(accountsToLoad: [saved])
        let auth = IdentityReconcilerProbe(reconciledAccounts: [saved])
        let resolver = SavedAccountIdentityResolver(
            liveIdentitySource: CurrentIdentityFixture(fingerprint: nil, stableAccountID: nil),
            storedAccountReconciler: auth
        )
        let useCase = LoadAccountsUseCase(
            repository: repository,
            identityResolver: resolver
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

        let repository = LoadingAccountCatalogProbe(accountsToLoad: [saved])
        let auth = IdentityReconcilerProbe(reconciledAccounts: [reconciled])
        let resolver = SavedAccountIdentityResolver(
            liveIdentitySource: CurrentIdentityFixture(fingerprint: nil, stableAccountID: "acct-123"),
            storedAccountReconciler: auth
        )
        let useCase = LoadAccountsUseCase(
            repository: repository,
            identityResolver: resolver
        )

        let result = try useCase.run()

        #expect(repository.savedAccounts == [reconciled])
        #expect(result.activeAccountID == id)
    }

    @Test
    func runResolvesActiveAccountUsingBackfilledScopedPrincipalIdentity() throws {
        let businessOneID = UUID()
        let businessTwoID = UUID()

        let savedBusinessOne = CodexAccount(
            id: businessOneID,
            name: "Business 1",
            snapshotFileName: "\(businessOneID.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "admin@raphh.me",
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: nil,
                snapshotFingerprint: "business-one-fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "admin@raphh.me")
            )
        )
        let savedBusinessTwo = CodexAccount(
            id: businessTwoID,
            name: "Business 2",
            snapshotFileName: "\(businessTwoID.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: nil,
                snapshotFingerprint: "business-two-fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@gmail.com")
            )
        )

        let reconciledBusinessOne = CodexAccount(
            id: businessOneID,
            name: "Business 1",
            snapshotFileName: "\(businessOneID.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "admin@raphh.me",
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: "acct-team",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|business-1",
                    chatGPTUserID: "user-business-1"
                ),
                workspaceIdentity: CodexWorkspaceIdentity(
                    workspaceAccountID: "org-business-1",
                    workspaceLabel: "Personal"
                ),
                snapshotFingerprint: "business-one-fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "admin@raphh.me")
            )
        )
        let reconciledBusinessTwo = CodexAccount(
            id: businessTwoID,
            name: "Business 2",
            snapshotFileName: "\(businessTwoID.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: "acct-team",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|business-2",
                    chatGPTUserID: "user-business-2"
                ),
                workspaceIdentity: CodexWorkspaceIdentity(
                    workspaceAccountID: "org-business-2",
                    workspaceLabel: "Personal"
                ),
                snapshotFingerprint: "business-two-fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@gmail.com")
            )
        )

        let repository = LoadingAccountCatalogProbe(accountsToLoad: [savedBusinessOne, savedBusinessTwo])
        let auth = IdentityReconcilerProbe(reconciledAccounts: [reconciledBusinessOne, reconciledBusinessTwo])
        let resolver = SavedAccountIdentityResolver(
            liveIdentitySource: CurrentIdentityFixture(
                fingerprint: nil,
                stableAccountID: "acct-team",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(
                    subject: "auth0|business-2",
                    chatGPTUserID: "user-business-2"
                )
            ),
            storedAccountReconciler: auth
        )
        let useCase = LoadAccountsUseCase(
            repository: repository,
            identityResolver: resolver
        )

        let result = try useCase.run()

        #expect(repository.savedAccounts == [reconciledBusinessOne, reconciledBusinessTwo])
        #expect(result.activeAccountID == businessTwoID)
    }

    @Test
    func runResolvesActiveAccountUsingLiveRemoteIdentityWhenOtherSignalsMiss() throws {
        let personalID = UUID()
        let businessID = UUID()
        let personal = CodexAccount(
            id: personalID,
            name: "Personal 1",
            snapshotFileName: "\(personalID.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "admin@raphh.me",
            planType: "plus",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: "acct-shared",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(subject: "auth0|personal", chatGPTUserID: "user-personal"),
                workspaceIdentity: CodexWorkspaceIdentity(workspaceAccountID: "org-personal", workspaceLabel: "Personal"),
                snapshotFingerprint: "personal-fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "admin@raphh.me")
            )
        )
        let business = CodexAccount(
            id: businessID,
            name: "Business 2",
            snapshotFileName: "\(businessID.uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "raphaelgrau@gmail.com",
            planType: "team",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: "acct-shared",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(subject: "auth0|business", chatGPTUserID: "user-business"),
                workspaceIdentity: CodexWorkspaceIdentity(workspaceAccountID: "org-business", workspaceLabel: "Business"),
                snapshotFingerprint: "business-fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@gmail.com")
            )
        )

        let repository = LoadingAccountCatalogProbe(accountsToLoad: [personal, business])
        let auth = IdentityReconcilerProbe(reconciledAccounts: [personal, business])
        let resolver = SavedAccountIdentityResolver(
            liveIdentitySource: CurrentIdentityFixture(
                fingerprint: nil,
                stableAccountID: "acct-shared",
                authPrincipalIdentity: CodexAuthPrincipalIdentity(subject: "auth0|missing", chatGPTUserID: "user-missing"),
                workspaceIdentity: CodexWorkspaceIdentity(workspaceAccountID: "org-missing", workspaceLabel: "Missing"),
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@gmail.com")
            ),
            storedAccountReconciler: auth
        )

        let result = try LoadAccountsUseCase(
            repository: repository,
            identityResolver: resolver
        ).run()

        #expect(result.activeAccountID == nil)
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

private final class LoadingAccountCatalogProbe: AccountCatalogLoader {
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

private final class IdentityReconcilerProbe: StoredAccountIdentityReconciler {
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

private struct CurrentIdentityFixture: LiveCodexAccountIdentitySource {
    let fingerprint: String?
    let stableAccountID: String?
    let authPrincipalIdentity: CodexAuthPrincipalIdentity?
    let workspaceIdentity: CodexWorkspaceIdentity?
    let remoteIdentity: CodexRemoteAccountIdentity?

    init(
        fingerprint: String?,
        stableAccountID: String?,
        authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil,
        workspaceIdentity: CodexWorkspaceIdentity? = nil,
        remoteIdentity: CodexRemoteAccountIdentity? = nil
    ) {
        self.fingerprint = fingerprint
        self.stableAccountID = stableAccountID
        self.authPrincipalIdentity = authPrincipalIdentity
        self.workspaceIdentity = workspaceIdentity
        self.remoteIdentity = remoteIdentity
    }

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(
            stableAccountID: stableAccountID,
            authPrincipalIdentity: authPrincipalIdentity,
            workspaceIdentity: workspaceIdentity,
            snapshotFingerprint: fingerprint,
            remoteIdentity: remoteIdentity
        )
    }
}
