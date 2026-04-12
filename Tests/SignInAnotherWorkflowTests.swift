import Foundation
import Testing

@testable import CodexPill

struct SignInAnotherWorkflowTests {
    @Test
    func prepareClearsAuthAndReturnsResolvedName() throws {
        let auth = SignInAnotherAuthSpy(savedAccount: makeAccount(name: "ignored", fingerprint: "fingerprint"))
        let appController = AppControllerSpy()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            appController: appController,
            appServerClient: AppServerSpy(status: CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)),
            repository: RepositorySpy(),
            activeAccountResolver: ActiveAccountResolver(authService: auth)
        )

        let result = try workflow.prepare(named: "  Secondary  ")

        #expect(auth.prepareForNewSignInCount == 1)
        #expect(appController.relaunchCount == 0)
        #expect(result.pendingAccountName == "Secondary")
    }

    @Test
    func relaunchCodexDelegatesToAppController() async throws {
        let auth = SignInAnotherAuthSpy(savedAccount: makeAccount(name: "ignored", fingerprint: "fingerprint"))
        let appController = AppControllerSpy()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            appController: appController,
            appServerClient: AppServerSpy(status: CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)),
            repository: RepositorySpy(),
            activeAccountResolver: ActiveAccountResolver(authService: auth)
        )

        try await workflow.relaunchCodex()

        #expect(appController.relaunchCount == 1)
    }

    @Test
    func completePendingSignInPersistsSavedAccountAndResolvesActiveID() async throws {
        let auth = SignInAnotherAuthSpy(
            savedAccount: makeAccount(name: "ignored", fingerprint: "live-fingerprint"),
            currentAuthData: Data("auth".utf8),
            currentFingerprint: "live-fingerprint"
        )
        let repository = RepositorySpy()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            appController: AppControllerSpy(),
            appServerClient: AppServerSpy(status: CodexAccountStatus(email: "person@example.com", planType: "pro", rateLimits: nil)),
            repository: repository,
            activeAccountResolver: ActiveAccountResolver(authService: auth)
        )

        let result = try await workflow.completePendingSignIn(
            pendingAccountName: "Second",
            existingAccounts: []
        )

        #expect(auth.savedNames == ["Second"])
        #expect(repository.savedAccounts?.count == 1)
        #expect(result?.savedAccount.email == "person@example.com")
        #expect(result?.activeAccountID == auth.savedAccount.id)
    }

    @Test
    func completePendingSignInUpdatesMatchedExistingAccountInsteadOfAppendingDuplicate() async throws {
        let existing = makeAccount(name: "Business 1", fingerprint: "live-fingerprint")
        let auth = SignInAnotherAuthSpy(
            savedAccount: existing,
            currentAuthData: Data("auth".utf8),
            currentFingerprint: "live-fingerprint"
        )
        let repository = RepositorySpy()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            appController: AppControllerSpy(),
            appServerClient: AppServerSpy(status: CodexAccountStatus(email: "admin@raphh.me", planType: "team", rateLimits: nil)),
            repository: repository,
            activeAccountResolver: ActiveAccountResolver(authService: auth)
        )

        let result = try await workflow.completePendingSignIn(
            pendingAccountName: "Business 2",
            existingAccounts: [existing]
        )

        #expect(auth.savedNames == ["Business 1"])
        #expect(repository.savedAccounts?.count == 1)
        #expect(repository.savedAccounts?.first?.id == existing.id)
        #expect(repository.savedAccounts?.first?.name == "Business 1")
        #expect(result?.activeAccountID == existing.id)
    }

    @Test
    func completePendingSignInDoesNotReuseExistingAccountBasedOnlyOnSharedEmail() async throws {
        let personal = CodexAccount(
            id: UUID(),
            name: "Personal",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "raphaelgrau@gmail.com",
            planType: "plus",
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: "personal-account",
                snapshotFingerprint: "personal-fingerprint",
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "raphaelgrau@gmail.com")
            )
        )
        let business = CodexAccount(
            id: UUID(),
            name: "Business 2",
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: "business-account",
                snapshotFingerprint: "business-fingerprint",
                remoteIdentity: nil
            )
        )
        let auth = SignInAnotherAuthSpy(
            savedAccount: business,
            currentAuthData: Data("auth".utf8),
            currentFingerprint: "business-fingerprint",
            currentStableAccountID: "business-account"
        )
        let repository = RepositorySpy()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            appController: AppControllerSpy(),
            appServerClient: AppServerSpy(status: CodexAccountStatus(email: "raphaelgrau@gmail.com", planType: "team", rateLimits: nil)),
            repository: repository,
            activeAccountResolver: ActiveAccountResolver(authService: auth)
        )

        let result = try await workflow.completePendingSignIn(
            pendingAccountName: "Business 2",
            existingAccounts: [personal]
        )

        #expect(repository.savedAccounts?.count == 2)
        #expect(repository.savedAccounts?.contains(where: { $0.id == personal.id }) == true)
        #expect(repository.savedAccounts?.contains(where: { $0.id == business.id }) == true)
        #expect(result?.activeAccountID == business.id)
    }

    private func makeAccount(name: String, fingerprint: String) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: nil,
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: nil,
                snapshotFingerprint: fingerprint,
                remoteIdentity: nil
            )
        )
    }
}

private final class SignInAnotherAuthSpy: CodexSignInAnotherAuthHandling {
    let savedAccount: CodexAccount
    let currentAuthData: Data?
    let currentFingerprint: String?
    let stableAccountIDValue: String?
    var prepareForNewSignInCount = 0
    var savedNames: [String] = []

    init(
        savedAccount: CodexAccount,
        currentAuthData: Data? = nil,
        currentFingerprint: String? = nil,
        currentStableAccountID: String? = nil
    ) {
        self.savedAccount = savedAccount
        self.currentAuthData = currentAuthData
        self.currentFingerprint = currentFingerprint
        self.stableAccountIDValue = currentStableAccountID
    }

    func prepareForNewSignIn() throws {
        prepareForNewSignInCount += 1
    }

    func readCurrentAuthData() throws -> Data {
        guard let currentAuthData else {
            throw NSError(domain: "SignInAnotherWorkflowTests", code: 1)
        }
        return currentAuthData
    }

    func currentAuthFingerprint() -> String? {
        currentFingerprint
    }

    func currentStableAccountID() -> String? {
        stableAccountIDValue
    }

    func saveCurrentAuthSnapshot(named name: String, existing: CodexAccount?) throws -> CodexAccount {
        savedNames.append(name)
        return savedAccount
    }
}

private final class AppControllerSpy: CodexAppRelaunching {
    var relaunchCount = 0

    func relaunchCodex() async throws {
        relaunchCount += 1
    }
}

private final class AppServerSpy: CodexAccountStatusReading {
    let status: CodexAccountStatus

    init(status: CodexAccountStatus) {
        self.status = status
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        status
    }
}

private final class RepositorySpy: AccountCatalogPersisting {
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}
