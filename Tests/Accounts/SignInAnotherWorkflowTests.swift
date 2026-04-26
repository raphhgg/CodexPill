import Foundation
import Testing

@testable import CodexPill

struct SignInAnotherWorkflowTests {
    @Test
    func prepareClearsLiveAuthAndDoesNotRelaunchUntilRequested() throws {
        let auth = SignInAnotherAuthSpy(savedAccount: makeAccount(name: "ignored", fingerprint: "fingerprint"))
        let processClient = SignInAnotherCodexProcessSpy()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            codexAppProcessClient: processClient,
            accountStatusClient: SignInAnotherStatusReader(status: CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)),
            repository: SignInAnotherRepositorySpy(),
            identityResolver: makeResolver(auth: auth)
        )

        let result = try workflow.prepare(named: "  Secondary  ", existingAccounts: [])

        #expect(result.pendingAccountName == "Secondary")
        #expect(auth.prepareForNewSignInCount == 1)
        #expect(processClient.availabilityCheckCount == 1)
        #expect(processClient.relaunchCount == 0)
    }

    @Test
    func prepareRejectsDuplicateNameBeforeClearingLiveAuthOrCheckingCodexAvailability() {
        let existing = makeAccount(name: "Business 1", fingerprint: "business-1")
        let auth = SignInAnotherAuthSpy(savedAccount: makeAccount(name: "ignored", fingerprint: "fingerprint"))
        let processClient = SignInAnotherCodexProcessSpy()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            codexAppProcessClient: processClient,
            accountStatusClient: SignInAnotherStatusReader(status: CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)),
            repository: SignInAnotherRepositorySpy(),
            identityResolver: makeResolver(auth: auth)
        )

        #expect(throws: SaveCurrentAccountWorkflowError.duplicateAccountName) {
            _ = try workflow.prepare(named: " business 1 ", existingAccounts: [existing])
        }
        #expect(auth.prepareForNewSignInCount == 0)
        #expect(processClient.availabilityCheckCount == 0)
        #expect(processClient.relaunchCount == 0)
    }

    @Test
    func completePendingSignInSkipsUntilLiveAuthExists() async throws {
        let auth = SignInAnotherAuthSpy(
            savedAccount: makeAccount(name: "ignored", fingerprint: "fingerprint"),
            currentAuthData: nil
        )
        let repository = SignInAnotherRepositorySpy()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            codexAppProcessClient: SignInAnotherCodexProcessSpy(),
            accountStatusClient: SignInAnotherStatusReader(status: CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)),
            repository: repository,
            identityResolver: makeResolver(auth: auth)
        )

        let result = try await workflow.completePendingSignIn(
            pendingAccountName: "Secondary",
            existingAccounts: []
        )

        #expect(result == nil)
        #expect(repository.savedAccounts == nil)
    }

    @Test
    func completePendingSignInPersistsLiveAuthWhenCodexAppWritesIt() async throws {
        let account = makeAccount(name: "ignored", fingerprint: "live-fingerprint")
        let auth = SignInAnotherAuthSpy(
            savedAccount: account,
            currentAuthData: Data("auth".utf8),
            currentFingerprint: "live-fingerprint"
        )
        let repository = SignInAnotherRepositorySpy()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            codexAppProcessClient: SignInAnotherCodexProcessSpy(),
            accountStatusClient: SignInAnotherStatusReader(
                status: CodexAccountStatus(email: "person@example.com", planType: "pro", rateLimits: nil)
            ),
            repository: repository,
            identityResolver: makeResolver(auth: auth)
        )

        let result = try await workflow.completePendingSignIn(
            pendingAccountName: "Secondary",
            existingAccounts: []
        )

        #expect(auth.savedNames == ["Secondary"])
        #expect(repository.savedAccounts?.count == 1)
        #expect(result?.savedAccount.email == "person@example.com")
        #expect(result?.savedAccount.planType == "pro")
        #expect(result?.activeAccountID == account.id)
    }
}

private func makeResolver(auth: SignInAnotherAuthSpy) -> SavedAccountIdentityResolver {
    SavedAccountIdentityResolver(
        liveIdentityReader: auth,
        storedAccountReconciler: SignInAnotherStoredIdentityPassthrough()
    )
}

private func makeAccount(name: String, fingerprint: String) -> CodexAccount {
    let id = UUID()
    return CodexAccount(
        id: id,
        name: name,
        snapshotFileName: "\(id.uuidString).json",
        createdAt: .distantPast,
        updatedAt: .distantPast,
        email: nil,
        planType: nil,
        rateLimits: nil,
        identity: CodexAccountIdentity(snapshotFingerprint: fingerprint)
    )
}

private final class SignInAnotherAuthSpy: CodexSignInAnotherAuthHandling, LiveCodexAccountIdentityReading {
    let savedAccount: CodexAccount
    var currentAuthData: Data?
    var currentFingerprint: String?
    private(set) var prepareForNewSignInCount = 0
    private(set) var savedNames: [String] = []

    init(
        savedAccount: CodexAccount,
        currentAuthData: Data? = Data("auth".utf8),
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
            throw CocoaError(.fileReadNoSuchFile)
        }
        return currentAuthData
    }

    func saveCurrentAuthSnapshot(named name: String, existing: CodexAccount?) throws -> CodexAccount {
        savedNames.append(name)
        var account = existing ?? savedAccount
        account.name = existing?.name ?? name
        return account
    }

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: currentFingerprint)
    }
}

private final class SignInAnotherCodexProcessSpy: CodexAppProcessClient {
    private(set) var availabilityCheckCount = 0
    private(set) var relaunchCount = 0

    func assertCodexAvailable() throws {
        availabilityCheckCount += 1
    }

    func relaunchCodex() async throws {
        relaunchCount += 1
    }
}

private struct SignInAnotherStatusReader: CodexAccountStatusClient {
    let status: CodexAccountStatus

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        status
    }
}

private final class SignInAnotherRepositorySpy: AccountCatalogStore {
    private(set) var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}

private struct SignInAnotherStoredIdentityPassthrough: StoredAccountIdentityReconciling {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
