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
    var prepareForNewSignInCount = 0
    var savedNames: [String] = []

    init(
        savedAccount: CodexAccount,
        currentAuthData: Data? = nil,
        currentFingerprint: String? = nil
    ) {
        self.savedAccount = savedAccount
        self.currentAuthData = currentAuthData
        self.currentFingerprint = currentFingerprint
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
