import Foundation
import Testing

@testable import CodexPill

struct MenuBarMenuStateTests {
    @Test
    func visibleAndOverflowAccountsRespectConfiguredLimit() {
        let accounts = [
            makeAccount(name: "A"),
            makeAccount(name: "B"),
            makeAccount(name: "C")
        ]

        let state = makeState(inactiveAccounts: accounts, visibleInactiveAccountCount: 2)

        #expect(state.visibleInactiveAccounts.map(\.name) == ["A", "B"])
        #expect(state.overflowInactiveAccounts.map(\.name) == ["C"])
    }

    @Test
    func zeroVisibleCountShowsAllAccountsWithoutOverflow() {
        let accounts = [
            makeAccount(name: "A"),
            makeAccount(name: "B")
        ]

        let state = makeState(inactiveAccounts: accounts, visibleInactiveAccountCount: 0)

        #expect(state.visibleInactiveAccounts.map(\.name) == ["A", "B"])
        #expect(state.overflowInactiveAccounts.isEmpty)
    }

    @Test
    func busyStateDisablesInteractiveActions() {
        let state = makeState(activeAccount: nil, inactiveAccounts: [], isBusy: true)

        #expect(!state.canSaveCurrentAccount)
        #expect(!state.canSignInAnotherAccount)
        #expect(!state.canShowAbout)
    }

    @Test
    func activeSavedAccountDisablesSaveCurrentAccount() {
        let state = makeState(activeAccount: makeAccount(name: "Active"), inactiveAccounts: [], isBusy: false)

        #expect(!state.canSaveCurrentAccount)
        #expect(state.canSignInAnotherAccount)
    }

    @Test
    func statusMessageOnlyShowsWhileBusy() {
        let hidden = makeState(inactiveAccounts: [], isBusy: false, statusMessage: "Refreshing...")
        let shown = makeState(inactiveAccounts: [], isBusy: true, statusMessage: "Refreshing...")

        #expect(!hidden.shouldShowStatusMessage)
        #expect(shown.shouldShowStatusMessage)
    }

    @Test
    func removeAccountsIsAvailableWhenSavedAccountsExist() {
        let state = makeState(activeAccount: makeAccount(name: "Active"), inactiveAccounts: [makeAccount(name: "Other")])

        #expect(state.canRemoveSavedAccounts)
        #expect(state.canRenameSavedAccounts)
        #expect(state.allSavedAccounts.map(\.name) == ["Active", "Other"])
    }

    @Test
    func saveCurrentAccountIsAllowedWhenThereAreNoSavedAccounts() {
        let state = makeState(activeAccount: nil, inactiveAccounts: [], isBusy: false)

        #expect(state.canSaveCurrentAccount)
        #expect(state.allSavedAccounts.isEmpty)
    }

    private func makeState(
        activeAccount: CodexAccount? = nil,
        inactiveAccounts: [CodexAccount],
        visibleInactiveAccountCount: Int = 2,
        isBusy: Bool = false,
        statusMessage: String = "Ready"
    ) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            inactiveAccounts: inactiveAccounts,
            visibleInactiveAccountCount: visibleInactiveAccountCount,
            visibleInactiveAccountCountOptions: [0, 2, 4],
            refreshIntervalMinutes: 5,
            refreshIntervalOptions: [1, 5, 10],
            statusBarMonochrome: false,
            statusBarIndicatorStyle: .dualArcBadge,
            isBusy: isBusy,
            statusMessage: statusMessage
        )
    }

    private func makeAccount(name: String) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: "\(name.lowercased())@example.com",
            planType: nil,
            rateLimits: nil,
            identity: CodexAccountIdentity(
                snapshotFingerprint: UUID().uuidString,
                remoteIdentity: CodexRemoteAccountIdentity(emailAddress: "\(name.lowercased())@example.com")
            )
        )
    }
}
