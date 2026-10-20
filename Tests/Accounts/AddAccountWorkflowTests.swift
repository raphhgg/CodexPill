import Foundation
import Testing

@testable import rusage

struct AddAccountWorkflowTests {
    @Test
    func completeIsolatedAddAccountPersistsCapturedAuthWithoutChangingActiveAccount() async throws {
        let activeAccountID = UUID()
        let active = makeAccount(id: activeAccountID, email: "personal@example.com", fingerprint: "live-fingerprint")
        let captured = makeAccount(email: "business@example.com", fingerprint: "isolated-fingerprint")
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

        let session = try await workflow.startIsolatedAddAccount()
        let result = try await workflow.completeIsolatedAddAccount(
            session,
            existingAccounts: [active],
            activeAccountID: activeAccountID
        )

        #expect(auth.savedAuthData == [Data("isolated-auth".utf8)])
        #expect(repository.savedAccounts?.map(\.email) == ["business@example.com", "personal@example.com"])
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
        let active = makeAccount(id: activeAccountID, email: nil, fingerprint: "live-fingerprint")
        let captured = makeAccount(email: nil, fingerprint: "isolated-fingerprint")
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

        let session = try await workflow.startIsolatedAddAccount()
        auth.currentFingerprint = "changed-live-fingerprint"

        await #expect(throws: AddAccountWorkflowError.liveAuthChanged) {
            _ = try await workflow.completeIsolatedAddAccount(
                session,
                existingAccounts: [active],
                activeAccountID: activeAccountID
            )
        }
        #expect(auth.savedAuthData.isEmpty)
        #expect(repository.savedAccounts == nil)
        #expect(loginSession.cleanupCount == 1)
        #expect(loginSession.verifyLoginStatusCount == 1)
    }

    @Test
    func completeIsolatedAddAccountRejectsAlreadySavedCapturedIdentity() async throws {
        let existing = makeAccount(email: nil, fingerprint: "isolated-fingerprint")
        let captured = makeAccount(email: nil, fingerprint: "isolated-fingerprint")
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

        let session = try await workflow.startIsolatedAddAccount()

        await #expect(throws: AddAccountWorkflowError.accountAlreadySaved(existing.id)) {
            _ = try await workflow.completeIsolatedAddAccount(
                session,
                existingAccounts: [existing],
                activeAccountID: existing.id
            )
        }
        #expect(auth.savedAuthData.isEmpty)
        #expect(repository.savedAccounts == nil)
        #expect(loginSession.cleanupCount == 1)
    }

    @Test
    func completeIsolatedAddAccountMapsCatalogSaveFailureAfterCapture() async throws {
        let active = makeAccount(email: nil, fingerprint: "live-fingerprint")
        let captured = makeAccount(email: nil, fingerprint: "isolated-fingerprint")
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

        let session = try await workflow.startIsolatedAddAccount()

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
        let active = makeAccount(email: nil, fingerprint: "live-fingerprint")
        let captured = makeAccount(email: nil, fingerprint: "isolated-fingerprint")
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

        let session = try await workflow.startIsolatedAddAccount()

        await #expect(throws: AddAccountWorkflowError.catalogSaveFailed) {
            _ = try await workflow.completeIsolatedAddAccount(
                session,
                existingAccounts: [active],
                activeAccountID: active.id
            )
        }
        #expect(auth.savedAuthData == [Data("isolated-auth".utf8)])
        #expect(auth.deletedSnapshotIDs == [captured.id])
        #expect(repository.savedAccounts == nil)
        #expect(loginSession.cleanupCount == 1)
    }

    @Test
    func cancelIsolatedAddAccountTerminatesLoginAndCleansTemporaryHome() async throws {
        let auth = AddAccountAuthSnapshotProbe(
            savedAccount: makeAccount(email: nil, fingerprint: "isolated-fingerprint"),
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

        let session = try await workflow.startIsolatedAddAccount()
        workflow.cancelIsolatedAddAccount(session)

        #expect(loginSession.cancelCount == 1)
        #expect(loginSession.cleanupCount == 1)
    }

}

private func makeResolver(auth: AddAccountAuthSnapshotProbe) -> SavedAccountIdentityResolver {
    SavedAccountIdentityResolver(
        liveIdentitySource: auth,
        storedAccountReconciler: PassthroughIdentityReconciler()
    )
}

private final class AddAccountAuthSnapshotProbe: CodexSignInAuthStore, LiveCodexAccountIdentitySource, @unchecked Sendable {
    let savedAccount: CodexAccount
    var currentAuthData: Data?
    var currentFingerprint: String?
    var capturedIdentity: LiveCodexAccountIdentity
    var saveAuthSnapshotError: Error?
    private(set) var savedAuthData: [Data] = []
    private(set) var deletedSnapshotIDs: [UUID] = []

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

    func saveAuthSnapshot(_ authData: Data, existing: CodexAccount?) throws -> CodexAccount {
        savedAuthData.append(authData)
        if let saveAuthSnapshotError {
            throw saveAuthSnapshotError
        }
        return existing ?? savedAccount
    }

    func deleteAuthSnapshot(for account: CodexAccount) throws {
        deletedSnapshotIDs.append(account.id)
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

private final class AddAccountCatalogProbe: AccountCatalogStore, @unchecked Sendable {
    private(set) var savedAccounts: [CodexAccount]?
    var saveError: Error?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        if let saveError {
            throw saveError
        }
        savedAccounts = accounts
    }
}

private final class AddAccountIsolatedLoginClientProbe: IsolatedCodexLoginClient, @unchecked Sendable {
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

private final class AddAccountIsolatedLoginSessionProbe: IsolatedCodexLoginSession, @unchecked Sendable {
    let prompt = IsolatedCodexLoginPrompt(
        url: URL(string: "https://auth.openai.com/codex/device")!,
        userCode: "ABCD-EFGH"
    )
    let codexHome = URL(fileURLWithPath: "/tmp/rusage-test-codex-home")

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
