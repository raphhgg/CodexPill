import Foundation
import Testing

@testable import CodexPill

struct DeleteSavedAccountUseCaseTests {
    @Test
    func runDeletesSnapshotPersistsFilteredAccountsAndRecomputesActiveAccount() async throws {
        let current = makeAccount(name: "Current", fingerprint: "live")
        let other = makeAccount(name: "Other", fingerprint: "other")
        let repository = SnapshotDeletingAccountCatalogProbe()
        let resolver = SavedAccountIdentityResolver(
            liveIdentitySource: CurrentIdentityFixture(fingerprint: "other", stableAccountID: nil),
            storedAccountReconciler: IdentityReconcilerAdapter()
        )
        let useCase = DeleteSavedAccountUseCase(repository: repository, identityResolver: resolver)

        let result = try await useCase.run(account: current, accounts: [current, other])

        #expect(repository.deletedAccountIDs == [current.id])
        #expect(repository.savedAccounts == [other])
        #expect(result.accounts == [other])
        #expect(result.activeAccountID == other.id)
    }

    @Test
    func runSignsOutLocalAccountBeforeDeletingWhenRequested() async throws {
        let current = makeAccount(name: "Current", fingerprint: "live")
        let repository = SnapshotDeletingAccountCatalogProbe()
        let signerOut = CodexAuthSignerOutProbe()
        let resolver = SavedAccountIdentityResolver(
            liveIdentitySource: CurrentIdentityFixture(fingerprint: nil, stableAccountID: nil),
            storedAccountReconciler: IdentityReconcilerAdapter()
        )
        let useCase = DeleteSavedAccountUseCase(
            repository: repository,
            identityResolver: resolver,
            authSignerOut: signerOut
        )

        _ = try await useCase.run(account: current, accounts: [current], signOutLocalAccount: true)

        #expect(signerOut.signOutCallCount == 1)
        #expect(repository.deletedAccountIDs == [current.id])
        #expect(repository.savedAccounts == [])
    }

    @Test
    func runDoesNotDeleteSnapshotWhenLocalSignOutFails() async throws {
        let current = makeAccount(name: "Current", fingerprint: "live")
        let repository = SnapshotDeletingAccountCatalogProbe()
        let signerOut = CodexAuthSignerOutProbe(error: SignOutFixtureError.failed)
        let resolver = SavedAccountIdentityResolver(
            liveIdentitySource: CurrentIdentityFixture(fingerprint: nil, stableAccountID: nil),
            storedAccountReconciler: IdentityReconcilerAdapter()
        )
        let useCase = DeleteSavedAccountUseCase(
            repository: repository,
            identityResolver: resolver,
            authSignerOut: signerOut
        )

        await #expect(throws: SignOutFixtureError.failed) {
            _ = try await useCase.run(account: current, accounts: [current], signOutLocalAccount: true)
        }

        #expect(signerOut.signOutCallCount == 1)
        #expect(repository.deletedAccountIDs.isEmpty)
        #expect(repository.savedAccounts == nil)
    }

    @Test
    func localAuthSignOutRemovesAuthAndRelaunchesCodex() async throws {
        let repository = try makeRepository()
        try repository.bootstrapStorage()
        try Data("auth".utf8).write(to: repository.paths.codexAuthFile, options: .atomic)
        let processClient = CodexAppProcessProbe()
        let signerOut = CodexLocalAuthSignOut(
            authService: CodexAuthSnapshotService(repository: repository),
            codexAppProcessClient: processClient
        )

        try await signerOut.signOut()

        #expect(processClient.availabilityCheckCount == 1)
        #expect(processClient.relaunchCount == 1)
        #expect(!FileManager.default.fileExists(atPath: repository.paths.codexAuthFile.path))
    }

    private func makeRepository() throws -> AccountRepository {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeleteSavedAccountUseCaseTests-\(UUID().uuidString)", isDirectory: true)
        return try AccountRepository(
            environment: [AppRuntimeEnvironment.validationAppSupportDirectoryEnvironmentKey: directory.path]
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
            email: "\(name.lowercased())@example.com",
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                stableAccountID: nil,
                snapshotFingerprint: fingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com")
            )
        )
    }
}

private final class SnapshotDeletingAccountCatalogProbe: AccountSnapshotRemover, @unchecked Sendable {
    var deletedAccountIDs: [UUID] = []
    var savedAccounts: [CodexAccount]?

    func saveAccounts(_ accounts: [CodexAccount]) throws {
        savedAccounts = accounts
    }

    func deleteSnapshot(for account: CodexAccount) throws {
        deletedAccountIDs.append(account.id)
    }
}

private final class CodexAuthSignerOutProbe: CodexAuthSignerOut, @unchecked Sendable {
    private let error: Error?
    private(set) var signOutCallCount = 0

    init(error: Error? = nil) {
        self.error = error
    }

    func signOut() async throws {
        signOutCallCount += 1
        if let error {
            throw error
        }
    }
}

private enum SignOutFixtureError: Error {
    case failed
}

private final class CodexAppProcessProbe: CodexAppProcessClient, @unchecked Sendable {
    private(set) var availabilityCheckCount = 0
    private(set) var relaunchCount = 0

    func assertCodexAvailable() throws {
        availabilityCheckCount += 1
    }

    func relaunchCodex() async throws {
        relaunchCount += 1
    }
}

private struct CurrentIdentityFixture: LiveCodexAccountIdentitySource {
    let fingerprint: String?
    let stableAccountID: String?
    let authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil
    let workspaceIdentity: CodexWorkspaceIdentity? = nil

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(
            stableAccountID: stableAccountID,
            authPrincipalIdentity: authPrincipalIdentity,
            workspaceIdentity: workspaceIdentity,
            snapshotFingerprint: fingerprint
        )
    }
}

private struct IdentityReconcilerAdapter: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
