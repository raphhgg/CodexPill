import Foundation
import Testing

@testable import CodexPill

struct SignInAnotherWorkflowTests {
    @Test
    func prepareClearsLiveAuthAndDoesNotRelaunchUntilRequested() throws {
        let auth = SignInAnotherAuthSnapshotProbe(savedAccount: makeAccount(name: "ignored", fingerprint: "fingerprint"))
        let processClient = SignInAnotherCodexProcessProbe()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            codexAppProcessClient: processClient,
            accountStatusClient: SignInAnotherStatusFixture(status: CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)),
            repository: SignInAnotherAccountCatalogProbe(),
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
        let auth = SignInAnotherAuthSnapshotProbe(savedAccount: makeAccount(name: "ignored", fingerprint: "fingerprint"))
        let processClient = SignInAnotherCodexProcessProbe()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            codexAppProcessClient: processClient,
            accountStatusClient: SignInAnotherStatusFixture(status: CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)),
            repository: SignInAnotherAccountCatalogProbe(),
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
        let auth = SignInAnotherAuthSnapshotProbe(
            savedAccount: makeAccount(name: "ignored", fingerprint: "fingerprint"),
            currentAuthData: nil
        )
        let repository = SignInAnotherAccountCatalogProbe()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            codexAppProcessClient: SignInAnotherCodexProcessProbe(),
            accountStatusClient: SignInAnotherStatusFixture(status: CodexAccountStatus(email: nil, planType: nil, rateLimits: nil)),
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
        let auth = SignInAnotherAuthSnapshotProbe(
            savedAccount: account,
            currentAuthData: Data("auth".utf8),
            currentFingerprint: "live-fingerprint"
        )
        let repository = SignInAnotherAccountCatalogProbe()
        let workflow = SignInAnotherWorkflow(
            authService: auth,
            codexAppProcessClient: SignInAnotherCodexProcessProbe(),
            accountStatusClient: SignInAnotherStatusFixture(
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

private func makeResolver(auth: SignInAnotherAuthSnapshotProbe) -> SavedAccountIdentityResolver {
    SavedAccountIdentityResolver(
        liveIdentitySource: auth,
        storedAccountReconciler: SignInAnotherStoredIdentityAdapter()
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

private final class SignInAnotherAuthSnapshotProbe: CodexSignInAuthStore, LiveCodexAccountIdentitySource {
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

private final class SignInAnotherCodexProcessProbe: CodexAppProcessClient {
    private(set) var availabilityCheckCount = 0
    private(set) var relaunchCount = 0

    func assertCodexAvailable() throws {
        availabilityCheckCount += 1
    }

    func relaunchCodex() async throws {
        relaunchCount += 1
    }
}

private struct SignInAnotherStatusFixture: CodexAccountStatusClient {
    let status: CodexAccountStatus

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        status
    }
}

private final class SignInAnotherAccountCatalogProbe: AccountCatalogStore {
    private(set) var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}

private struct SignInAnotherStoredIdentityAdapter: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
