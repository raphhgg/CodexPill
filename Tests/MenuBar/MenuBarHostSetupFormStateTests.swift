import Foundation
import Testing

@testable import CodexPill

struct MenuBarHostSetupFormStateTests {
    @Test
    func submitStaysDisabledUntilConnectionTestSucceeds() {
        var state = MenuBarHostSetupFormState(
            destination: "",
            idleStatusText: "CodexPill checks the connection automatically."
        )

        #expect(!state.canSubmit)

        state.updateDestination("user@devbox")

        #expect(!state.canSubmit)
        #expect(state.statusMessage == "CodexPill checks the connection automatically.")
        #expect(state.statusKind == .idle)
    }

    @Test
    func successfulTestEnablesSubmitForMatchingDestination() {
        var state = MenuBarHostSetupFormState(
            destination: "user@devbox",
            idleStatusText: "CodexPill checks the connection automatically."
        )
        let host = RemoteHost(destination: "user@devbox")

        state.beginTesting()
        state.finishTesting(with: .success(host))

        #expect(state.isTesting == false)
        #expect(state.canSubmit)
        #expect(state.validatedHost == host)
        #expect(state.statusMessage == "Connection successful.")
        #expect(state.statusKind == .success)
    }

    @Test
    func editingDestinationAfterSuccessClearsValidatedHost() {
        var state = MenuBarHostSetupFormState(
            destination: "user@devbox",
            idleStatusText: "CodexPill checks the connection automatically."
        )

        state.finishTesting(with: .success(RemoteHost(destination: "user@devbox")))
        state.updateDestination("user@prod")

        #expect(state.validatedHost == nil)
        #expect(!state.canSubmit)
        #expect(state.statusMessage == "CodexPill checks the connection automatically.")
        #expect(state.statusKind == .idle)
    }

    @Test
    func failedTestShowsErrorAndKeepsSubmitDisabled() {
        var state = MenuBarHostSetupFormState(
            destination: "user@devbox",
            idleStatusText: "CodexPill checks the connection automatically."
        )

        state.beginTesting()
        state.finishTesting(with: .failure(RemoteHostClientError.commandFailed("Permission denied")))

        #expect(state.isTesting == false)
        #expect(!state.canSubmit)
        #expect(state.statusMessage == "Permission denied")
        #expect(state.statusKind == .failure)
    }

    @Test
    func beginTestingSetsTestingStatusKind() {
        var state = MenuBarHostSetupFormState(
            destination: "user@devbox",
            idleStatusText: "CodexPill checks the connection automatically."
        )

        state.beginTesting()

        #expect(state.isTesting)
        #expect(state.statusKind == .testing)
    }
}
