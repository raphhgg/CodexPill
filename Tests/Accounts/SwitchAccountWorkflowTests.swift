import Foundation
import Testing

@testable import Refill

struct SwitchAccountWorkflowTests {
    @Test
    func runActivatesPersistsRelaunchesAndReturnsMatchedAccount() async throws {
        let target = makeAccount(name: "Target", fingerprint: "live-fingerprint")
        let other = makeAccount(name: "Other", fingerprint: "other-fingerprint")

        let auth = AuthSnapshotProbe(currentFingerprint: "live-fingerprint", currentStableAccountID: nil)
        let repository = AccountCatalogProbe()
        let codexAppProcessClient = CodexAppProcessProbe()
        let workflow = SwitchAccountWorkflow(
            authService: auth,
            repository: repository,
            codexAppProcessClient: codexAppProcessClient,
            identityResolver: makeResolver(auth: auth)
        )

        let result = try await workflow.run(account: target, accounts: [target, other])

        #expect(auth.activatedAccountID == target.id)
        #expect(repository.savedAccounts?.map(\.id) == [target.id, other.id])
        #expect(result == SwitchAccountResult(activeAccountID: target.id, relaunch: .relaunched))
    }

    @Test
    func runSwitchesWithoutTheCodexApp() async throws {
        let target = makeAccount(name: "Target", fingerprint: "live-fingerprint")

        let auth = AuthSnapshotProbe(currentFingerprint: "live-fingerprint", currentStableAccountID: nil)
        let repository = AccountCatalogProbe()
        let codexAppProcessClient = CodexAppProcessProbe()
        codexAppProcessClient.relaunchResult = .appNotFound
        let workflow = SwitchAccountWorkflow(
            authService: auth,
            repository: repository,
            codexAppProcessClient: codexAppProcessClient,
            identityResolver: makeResolver(auth: auth)
        )

        let result = try await workflow.run(account: target, accounts: [target])

        #expect(auth.activatedAccountID == target.id)
        #expect(repository.savedAccounts?.map(\.id) == [target.id])
        #expect(result == SwitchAccountResult(activeAccountID: target.id, relaunch: .appNotFound))
    }

    @Test
    func runStillRelaunchesEvenWhenMatcherCannotResolveActiveAccount() async throws {
        let target = makeAccount(name: "Target", fingerprint: "saved-fingerprint")

        let auth = AuthSnapshotProbe(currentFingerprint: "different-fingerprint", currentStableAccountID: nil)
        let repository = AccountCatalogProbe()
        let codexAppProcessClient = CodexAppProcessProbe()
        let workflow = SwitchAccountWorkflow(
            authService: auth,
            repository: repository,
            codexAppProcessClient: codexAppProcessClient,
            identityResolver: makeResolver(auth: auth)
        )

        let result = try await workflow.run(account: target, accounts: [target])

        #expect(result == SwitchAccountResult(activeAccountID: nil, relaunch: .relaunched))
    }
}

private final class AuthSnapshotProbe: CodexAuthActivator, LiveCodexAccountIdentitySource, @unchecked Sendable {
    var activatedAccountID: UUID?
    private let fingerprint: String?
    private let stableAccountID: String?
    private let authPrincipalIdentity: CodexAuthPrincipalIdentity?
    private let workspaceIdentity: CodexWorkspaceIdentity?

    init(
        currentFingerprint: String?,
        currentStableAccountID: String?,
        currentAuthPrincipalIdentity: CodexAuthPrincipalIdentity? = nil,
        currentWorkspaceIdentity: CodexWorkspaceIdentity? = nil
    ) {
        self.fingerprint = currentFingerprint
        self.stableAccountID = currentStableAccountID
        self.authPrincipalIdentity = currentAuthPrincipalIdentity
        self.workspaceIdentity = currentWorkspaceIdentity
    }

    func activate(_ account: CodexAccount) throws {
        activatedAccountID = account.id
    }

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(
            stableAccountID: stableAccountID,
            authPrincipalIdentity: authPrincipalIdentity,
            workspaceIdentity: workspaceIdentity,
            snapshotFingerprint: fingerprint
        )
    }
}

private final class AccountCatalogProbe: AccountCatalogStore, @unchecked Sendable {
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }
}

private func makeResolver(auth: AuthSnapshotProbe) -> SavedAccountIdentityResolver {
    SavedAccountIdentityResolver(
        liveIdentitySource: auth,
        storedAccountReconciler: PassthroughIdentityReconciler()
    )
}
