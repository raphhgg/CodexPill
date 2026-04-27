import Foundation
import Testing

@testable import CodexPill

struct AccountCatalogStateTests {
    @Test
    func applySavedAccountInsertsSortsAndUpdatesActiveAccount() {
        var state = AccountCatalogState()
        let existing = makeAccount(name: "Zulu", fingerprint: "z")
        state.applyLoad(
            LoadAccountsResult(
                accounts: [existing],
                activeAccountID: existing.id
            )
        )
        let newAccount = makeAccount(name: "Alpha", fingerprint: "a")

        state.applySavedAccount(newAccount, activeAccountID: newAccount.id)

        #expect(state.accounts.map(\.name) == ["Alpha", "Zulu"])
        #expect(state.activeAccountID == newAccount.id)
        #expect(state.activeAccount?.id == newAccount.id)
        #expect(state.inactiveAccounts.map(\.id) == [existing.id])
    }

    @Test
    func applySavedAccountReplacesExistingAccountByID() {
        var state = AccountCatalogState()
        let original = makeAccount(name: "Business 4", fingerprint: "old")
        state.applyLoad(
            LoadAccountsResult(
                accounts: [original],
                activeAccountID: original.id
            )
        )
        var updated = original
        updated.planType = "pro"

        state.applySavedAccount(updated, activeAccountID: original.id)

        #expect(state.accounts.count == 1)
        #expect(state.accounts[0].planType == "pro")
    }

    @Test
    func applyResultHelpersReplaceCatalogAndActiveAccount() {
        let active = makeAccount(name: "Active", fingerprint: "a")
        let other = makeAccount(name: "Other", fingerprint: "b")
        let refreshed = makeAccount(name: "Refreshed", fingerprint: "c")
        var state = AccountCatalogState()

        state.applyDeleted(
            DeleteSavedAccountResult(
                accounts: [active],
                activeAccountID: active.id
            )
        )
        #expect(state.accounts == [active])
        #expect(state.activeAccountID == active.id)

        state.applyHydrated(
            HydrateSavedAccountsMetadataResult(
                accounts: [active, other],
                activeAccountID: active.id,
                hydratedAccountIDs: [other.id]
            )
        )
        #expect(state.accounts == [active, other])
        #expect(state.activeAccountID == active.id)

        state.applyRefreshed(
            RefreshActiveAccountResult(
                accounts: [refreshed, other],
                refreshedAccountID: refreshed.id
            )
        )
        #expect(state.accounts == [refreshed, other])
        #expect(state.activeAccountID == refreshed.id)
    }

    @Test
    func resolveActiveAccountIDUsesIdentityResolver() {
        let active = makeAccount(name: "Active", fingerprint: "live")
        let other = makeAccount(name: "Other", fingerprint: "other")
        let identityResolver = SavedAccountIdentityResolver(
            liveIdentitySource: AccountCatalogCurrentIdentityFixture(fingerprint: "live"),
            storedAccountReconciler: AccountCatalogStoredIdentityAdapter()
        )
        var state = AccountCatalogState()
        state.applyLoad(
            LoadAccountsResult(
                accounts: [other, active],
                activeAccountID: nil
            )
        )

        state.resolveActiveAccountID(using: identityResolver)

        #expect(state.activeAccountID == active.id)
        #expect(state.activeAccount?.id == active.id)
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
                snapshotFingerprint: fingerprint,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com")
            )
        )
    }
}

private struct AccountCatalogCurrentIdentityFixture: LiveCodexAccountIdentitySource {
    let fingerprint: String?

    func readCurrentLiveAccountIdentity() -> LiveCodexAccountIdentity {
        LiveCodexAccountIdentity(snapshotFingerprint: fingerprint)
    }
}

private struct AccountCatalogStoredIdentityAdapter: StoredAccountIdentityReconciler {
    func reconcileStoredAccountIdentities(_ accounts: [CodexAccount]) -> [CodexAccount] {
        accounts
    }
}
