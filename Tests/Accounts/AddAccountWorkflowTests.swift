import Foundation
import Testing

@testable import CodexPill

struct AddAccountWorkflowTests {
    @Test
    func isolatedAddAccountRejectsEmptyNameBeforeStartingLogin() async {
        let auth = AddAccountAuthSnapshotProbe(savedAccount: makeAccount(name: "ignored", fingerprint: "fingerprint"))
        let loginClient = AddAccountIsolatedLoginClientProbe()
        let workflow = AddAccountWorkflow(
            authService: auth,
            repository: AddAccountCatalogProbe(),
            identityResolver: makeResolver(auth: auth),
            isolatedLoginClient: loginClient
        )

        await #expect(throws: AccountDisplayNameError.emptyAccountName) {
            _ = try await workflow.startIsolatedAddAccount(named: "   ", existingAccounts: [])
        }
        #expect(loginClient.startLoginCount == 0)
    }

    @Test
    func isolatedAddAccountRejectsDuplicateNameBeforeStartingLogin() async {
        let existing = makeAccount(name: "Business 1", fingerprint: "business-1")
        let auth = AddAccountAuthSnapshotProbe(savedAccount: makeAccount(name: "ignored", fingerprint: "fingerprint"))
        let loginClient = AddAccountIsolatedLoginClientProbe()
        let workflow = AddAccountWorkflow(
            authService: auth,
            repository: AddAccountCatalogProbe(),
            identityResolver: makeResolver(auth: auth),
            isolatedLoginClient: loginClient
        )

        await #expect(throws: AccountDisplayNameError.duplicateAccountName) {
            _ = try await workflow.startIsolatedAddAccount(named: " business 1 ", existingAccounts: [existing])
        }
        #expect(loginClient.startLoginCount == 0)
    }

    @Test
    func completeIsolatedAddAccountPersistsCapturedAuthWithoutChangingActiveAccount() async throws {
        let activeAccountID = UUID()
        let active = makeAccount(id: activeAccountID, name: "Personal", fingerprint: "live-fingerprint")
        let captured = makeAccount(name: "Business 2", fingerprint: "isolated-fingerprint")
        let auth = AddAccountAuthSnapshotProbe(
            savedAccount: captured,
            currentAuthData: Data("live-auth".utf8),
            currentFingerprint: "live-fingerprint"
        )
        let repository = AddAccountCatalogProbe()
        let loginSession = AddAccountIsolatedLoginSessionProbe(authData: Data("isolated-auth".utf8))
        let loginClient = AddAccountIsolatedLoginClientProbe(session: loginSession)
        let workflow = AddAccountWorkflow(
            authService: auth,
            repository: repository,
            identityResolver: makeResolver(auth: auth),
            isolatedLoginClient: loginClient
        )

        let session = try await workflow.startIsolatedAddAccount(named: " Business 2 ", existingAccounts: [active])
        let result = try await workflow.completeIsolatedAddAccount(
            session,
            existingAccounts: [active],
            activeAccountID: activeAccountID
        )

        #expect(auth.savedNames == ["Business 2"])
        #expect(auth.savedAuthData == [Data("isolated-auth".utf8)])
        #expect(repository.savedAccounts?.map(\.name) == ["Business 2", "Personal"])
        #expect(result.savedAccount.id == captured.id)
        #expect(result.activeAccountID == activeAccountID)
        #expect(loginSession.waitForAuthDataCount == 1)
        #expect(loginSession.verifyLoginStatusCount == 1)
        #expect(loginSession.cleanupCount == 1)
        #expect(loginSession.cancelCount == 0)
    }

    @Test
    func completeIsolatedAddAccountAbortsWhenLiveAuthChangesDuringSignIn() async throws {
        let activeAccountID = UUID()
        let active = makeAccount(id: activeAccountID, name: "Personal", fingerprint: "live-fingerprint")
        let captured = makeAccount(name: "Business 2", fingerprint: "isolated-fingerprint")
        let auth = AddAccountAuthSnapshotProbe(
            savedAccount: captured,
            currentAuthData: Data("live-auth".utf8),
            currentFingerprint: "live-fingerprint"
        )
        let repository = AddAccountCatalogProbe()
        let loginSession = AddAccountIsolatedLoginSessionProbe(authData: Data("isolated-auth".utf8))
        let loginClient = AddAccountIsolatedLoginClientProbe(session: loginSession)
        let workflow = AddAccountWorkflow(
            authService: auth,
            repository: repository,
            identityResolver: makeResolver(auth: auth),
            isolatedLoginClient: loginClient
        )

        let session = try await workflow.startIsolatedAddAccount(named: " Business 2 ", existingAccounts: [active])
        auth.currentFingerprint = "changed-live-fingerprint"

        await #expect(throws: AddAccountWorkflowError.liveAuthChanged) {
            _ = try await workflow.completeIsolatedAddAccount(
                session,
                existingAccounts: [active],
                activeAccountID: activeAccountID
            )
        }
        #expect(auth.savedNames.isEmpty)
        #expect(auth.savedAuthData.isEmpty)
        #expect(repository.savedAccounts == nil)
        #expect(loginSession.cleanupCount == 1)
        #expect(loginSession.verifyLoginStatusCount == 1)
    }

    @Test
    func completeIsolatedAddAccountRejectsAlreadySavedCapturedIdentity() async throws {
        let existing = makeAccount(name: "Business 4", fingerprint: "isolated-fingerprint")
        let captured = makeAccount(name: "Business 7", fingerprint: "isolated-fingerprint")
        let auth = AddAccountAuthSnapshotProbe(
            savedAccount: captured,
            currentAuthData: Data("live-auth".utf8),
            currentFingerprint: "live-fingerprint",
            capturedIdentity: LiveCodexAccountIdentity(snapshotFingerprint: "isolated-fingerprint")
        )
        let repository = AddAccountCatalogProbe()
        let loginSession = AddAccountIsolatedLoginSessionProbe(authData: Data("isolated-auth".utf8))
        let workflow = AddAccountWorkflow(
            authService: auth,
            repository: repository,
            identityResolver: makeResolver(auth: auth),
            isolatedLoginClient: AddAccountIsolatedLoginClientProbe(session: loginSession)
        )

        let session = try await workflow.startIsolatedAddAccount(named: "Business 7", existingAccounts: [existing])

        await #expect(throws: AddAccountWorkflowError.accountAlreadySaved("Business 4")) {
            _ = try await workflow.completeIsolatedAddAccount(
                session,
                existingAccounts: [existing],
                activeAccountID: existing.id
            )
        }
        #expect(auth.savedNames.isEmpty)
        #expect(auth.savedAuthData.isEmpty)
        #expect(repository.savedAccounts == nil)
        #expect(loginSession.cleanupCount == 1)
    }

    @Test
    func completeIsolatedAddAccountMapsCatalogSaveFailureAfterCapture() async throws {
        let active = makeAccount(name: "Personal", fingerprint: "live-fingerprint")
        let captured = makeAccount(name: "Business 2", fingerprint: "isolated-fingerprint")
        let auth = AddAccountAuthSnapshotProbe(
            savedAccount: captured,
            currentAuthData: Data("live-auth".utf8),
            currentFingerprint: "live-fingerprint"
        )
        auth.saveAuthSnapshotError = CocoaError(.fileWriteUnknown)
        let repository = AddAccountCatalogProbe()
        let loginSession = AddAccountIsolatedLoginSessionProbe(authData: Data("isolated-auth".utf8))
        let workflow = AddAccountWorkflow(
            authService: auth,
            repository: repository,
            identityResolver: makeResolver(auth: auth),
            isolatedLoginClient: AddAccountIsolatedLoginClientProbe(session: loginSession)
        )

        let session = try await workflow.startIsolatedAddAccount(named: "Business 2", existingAccounts: [active])

        await #expect(throws: AddAccountWorkflowError.catalogSaveFailed) {
            _ = try await workflow.completeIsolatedAddAccount(
                session,
                existingAccounts: [active],
                activeAccountID: active.id
            )
        }
        #expect(auth.savedAuthData == [Data("isolated-auth".utf8)])
        #expect(repository.savedAccounts == nil)
        #expect(loginSession.cleanupCount == 1)
    }

    @Test
    func completeIsolatedAddAccountMapsRepositorySaveFailureAfterSnapshotSave() async throws {
        let active = makeAccount(name: "Personal", fingerprint: "live-fingerprint")
        let captured = makeAccount(name: "Business 2", fingerprint: "isolated-fingerprint")
        let auth = AddAccountAuthSnapshotProbe(
            savedAccount: captured,
            currentAuthData: Data("live-auth".utf8),
            currentFingerprint: "live-fingerprint"
        )
        let repository = AddAccountCatalogProbe()
        repository.saveError = CocoaError(.fileWriteOutOfSpace)
        let loginSession = AddAccountIsolatedLoginSessionProbe(authData: Data("isolated-auth".utf8))
        let workflow = AddAccountWorkflow(
            authService: auth,
            repository: repository,
            identityResolver: makeResolver(auth: auth),
            isolatedLoginClient: AddAccountIsolatedLoginClientProbe(session: loginSession)
        )

        let session = try await workflow.startIsolatedAddAccount(named: "Business 2", existingAccounts: [active])

        await #expect(throws: AddAccountWorkflowError.catalogSaveFailed) {
            _ = try await workflow.completeIsolatedAddAccount(
                session,
                existingAccounts: [active],
                activeAccountID: active.id
            )
        }
        #expect(auth.savedNames == ["Business 2"])
        #expect(auth.savedAuthData == [Data("isolated-auth".utf8)])
        #expect(auth.deletedSnapshotNames == ["Business 2"])
        #expect(repository.savedAccounts == nil)
        #expect(loginSession.cleanupCount == 1)
    }

    @Test
    func cancelIsolatedAddAccountTerminatesLoginAndCleansTemporaryHome() async throws {
        let auth = AddAccountAuthSnapshotProbe(
            savedAccount: makeAccount(name: "Business 2", fingerprint: "isolated-fingerprint"),
            currentAuthData: Data("live-auth".utf8),
            currentFingerprint: "live-fingerprint"
        )
        let loginSession = AddAccountIsolatedLoginSessionProbe(authData: Data("isolated-auth".utf8))
        let workflow = AddAccountWorkflow(
            authService: auth,
            repository: AddAccountCatalogProbe(),
            identityResolver: makeResolver(auth: auth),
            isolatedLoginClient: AddAccountIsolatedLoginClientProbe(session: loginSession)
        )

        let session = try await workflow.startIsolatedAddAccount(named: "Business 2", existingAccounts: [])
        workflow.cancelIsolatedAddAccount(session)

        #expect(loginSession.cancelCount == 1)
        #expect(loginSession.cleanupCount == 1)
    }

}

private func makeResolver(auth: AddAccountAuthSnapshotProbe) -> SavedAccountIdentityResolver {
    SavedAccountIdentityResolver(
        liveIdentitySource: auth,
        storedAccountReconciler: AddAccountStoredIdentityAdapter()
    )
}

private func makeAccount(id: UUID = UUID(), name: String, fingerprint: String) -> CodexAccount {
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

private final class AddAccountAuthSnapshotProbe: CodexSignInAuthStore, LiveCodexAccountIdentitySource {
    let savedAccount: CodexAccount
    var currentAuthData: Data?
    var currentFingerprint: String?
    var capturedIdentity: LiveCodexAccountIdentity
    var saveAuthSnapshotError: Error?
    private(set) var savedNames: [String] = []
    private(set) var savedAuthData: [Data] = []
    private(set) var deletedSnapshotNames: [String] = []

    init(
        savedAccount: CodexAccount,
        currentAuthData: Data? = Data("auth".utf8),
        currentFingerprint: String? = nil,
        capturedIdentity: LiveCodexAccountIdentity = .empty
    ) {
        self.savedAccount = savedAccount
        self.currentAuthData = currentAuthData
        self.currentFingerprint = currentFingerprint
        self.capturedIdentity = capturedIdentity
    }

    func readCurrentAuthData() throws -> Data {
        guard let currentAuthData else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return currentAuthData
    }

    func saveAuthSnapshot(_ authData: Data, named name: String, existing: CodexAccount?) throws -> CodexAccount {
        savedNames.append(name)
        savedAuthData.append(authData)
        if let saveAuthSnapshotError {
            throw saveAuthSnapshotError
        }
        var account = existing ?? savedAccount
        account.name = name
        return account
    }

    func deleteAuthSnapshot(for account: CodexAccount) throws {
        deletedSnapshotNames.append(account.name)
    }

    func currentAuthFingerprint() -> String? {
        currentFingerprint
    }

    func liveIdentity(forAuthData authData: Data) -> LiveCodexAccountIdentity {
        capturedIdentity
    }

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: currentFingerprint)
    }
}

private final class AddAccountCodexProcessProbe: CodexAppProcessClient {
    private(set) var availabilityCheckCount = 0
    private(set) var relaunchCount = 0

    func assertCodexAvailable() throws {
        availabilityCheckCount += 1
    }

    func relaunchCodex() async throws {
        relaunchCount += 1
    }
}

private struct AddAccountStatusFixture: CodexAccountStatusClient {
    let status: CodexAccountStatus

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        status
    }
}

private final class AddAccountCatalogProbe: AccountCatalogStore {
    private(set) var savedAccounts: [CodexAccount]?
    var saveError: Error?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        if let saveError {
            throw saveError
        }
        savedAccounts = accounts
    }
}

private struct AddAccountStoredIdentityAdapter: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}

private final class AddAccountIsolatedLoginClientProbe: IsolatedCodexLoginClient {
    private let session: AddAccountIsolatedLoginSessionProbe
    private(set) var startLoginCount = 0

    init(session: AddAccountIsolatedLoginSessionProbe = AddAccountIsolatedLoginSessionProbe()) {
        self.session = session
    }

    func startLogin() async throws -> IsolatedCodexLoginSession {
        startLoginCount += 1
        return session
    }
}

private final class AddAccountIsolatedLoginSessionProbe: IsolatedCodexLoginSession {
    let prompt = IsolatedCodexLoginPrompt(
        url: URL(string: "https://auth.openai.com/codex/device")!,
        userCode: "ABCD-EFGH"
    )
    let codexHome = URL(fileURLWithPath: "/tmp/codexpill-test-codex-home")

    private let authData: Data
    private(set) var waitForAuthDataCount = 0
    private(set) var verifyLoginStatusCount = 0
    private(set) var cancelCount = 0
    private(set) var cleanupCount = 0

    init(authData: Data = Data("isolated-auth".utf8)) {
        self.authData = authData
    }

    func waitForAuthData() async throws -> Data {
        waitForAuthDataCount += 1
        return authData
    }

    func verifyLoginStatus() async -> Bool {
        verifyLoginStatusCount += 1
        return true
    }

    func cancel() {
        cancelCount += 1
    }

    func cleanup() {
        cleanupCount += 1
    }
}
