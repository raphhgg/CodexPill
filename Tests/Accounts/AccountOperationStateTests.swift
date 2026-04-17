import Foundation
import Testing

@testable import CodexPill

@MainActor
struct AccountOperationStateTests {
    @Test
    func beginMarksBusyAndSetsStatus() {
        let state = AccountOperationState()

        state.begin(status: "Saving current Codex auth...")

        #expect(state.isBusy)
        #expect(state.statusMessage == "Saving current Codex auth...")
        #expect(state.pendingErrorMessage == nil)
    }

    @Test
    func succeedMarksDoneAndClearsBusy() {
        let state = AccountOperationState()
        state.begin(status: "Switching...")

        state.succeed()

        #expect(state.statusMessage == "Done")
        #expect(state.isBusy == false)
    }

    @Test
    func failReturnsToReadyStoresErrorAndClearsBusy() {
        let state = AccountOperationState()
        state.begin(status: "Switching...")

        state.fail(AccountOperationStateTestFailure.message("Switch failed."))

        #expect(state.statusMessage == "Ready")
        #expect(state.isBusy == false)
        #expect(state.pendingErrorMessage == "Switch failed.")
    }

    @Test
    func consumePendingErrorMessageReturnsAndClearsStoredError() {
        let state = AccountOperationState()
        state.fail(AccountOperationStateTestFailure.message("Background refresh failed."))

        #expect(state.consumePendingErrorMessage() == "Background refresh failed.")
        #expect(state.consumePendingErrorMessage() == nil)
    }

    @Test
    func setIdleStatusUpdatesMessageWithoutMarkingBusy() {
        let state = AccountOperationState()

        state.setIdleStatus("Loaded 3 account(s)")

        #expect(state.statusMessage == "Loaded 3 account(s)")
        #expect(state.isBusy == false)
    }
}

private enum AccountOperationStateTestFailure: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            message
        }
    }
}
