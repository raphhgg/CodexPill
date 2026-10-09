import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuBarValidationObserverTests {
    @Test
    func menuActionRecordsSameDispatchEventAndSnapshotTrace() throws {
        let sink = ValidationSinkProbe()
        let observer = MenuBarValidationObserver(
            sink: sink,
            scenario: "observer-tests"
        )

        observer.recordMenuAction(
            "switchAccount",
            payload: [
                "targetName": "Business",
                "message": "/Users/demo/.codex/auth.json"
            ],
            state: makeMenuState(),
            menu: nil,
            statusItemState: nil
        )

        let event = try #require(sink.events.first)
        #expect(event.scenario == "observer-tests")
        #expect(event.proofLayer == "live_ui")
        #expect(event.event == "menu_action_dispatched")
        #expect(event.step == "menu_action_dispatch")
        #expect(event.payload["action"] == "switchAccount")
        #expect(event.payload["targetName"] == "Business")
        #expect(event.payload["message"] == "/Users/<redacted>/.codex/auth.json")

        let snapshot = try #require(sink.snapshots.first)
        #expect(snapshot.actionTrace?.lastMenuAction == "switchAccount")
    }

    @Test
    func localSwitchObserverEventsPreserveInvariantIDsAndActionTrace() throws {
        let sink = ValidationSinkProbe()
        let observer = MenuBarValidationObserver(
            sink: sink,
            scenario: "observer-tests"
        )
        let previous = makeAccount(name: "Personal", email: "personal@example.com")
        let target = makeAccount(name: "Business", email: "business@example.com")

        observer.recordSwitchAccountMenuAction(
            targetAccount: target,
            activeAccount: previous,
            savedAccounts: [previous, target]
        )
        observer.recordSwitchConfirmationPresented(targetAccount: target)
        observer.recordSwitchConfirmationResult(accepted: true, targetAccount: target)
        observer.recordSwitchWorkflowStarted(targetAccount: target)
        _ = observer.recordActiveAccountTransitionIfNeeded(
            previousName: previous.name,
            currentID: target.id,
            currentName: target.name,
            activeAccount: target,
            savedAccounts: [previous, target]
        )
        observer.recordSnapshot(state: makeMenuState(activeAccount: target), menu: nil, statusItemState: nil)

        #expect(sink.events.map(\.event) == [
            "switch_confirmation_presented",
            "switch_confirmation_accepted",
            "switch_workflow_started",
            "active_account_changed"
        ])
        #expect(sink.events.last?.invariantIds == ["accounts.switch_account.menu_action_changes_active_account"])
        #expect(sink.events.last?.payload == [
            "fromName": "Personal",
            "toName": "Business"
        ])
        #expect(sink.snapshots.last?.actionTrace?.lastSwitchTargetName == "Business")
        #expect(sink.snapshots.last?.actionTrace?.lastConfirmationRequest == "switchAccount")
        #expect(sink.snapshots.last?.actionTrace?.lastConfirmationAccepted == true)
    }

    private func makeMenuState(activeAccount: CodexAccount? = nil) -> MenuBarMenuState {
        MenuBarMenuState(
            activeAccount: activeAccount,
            inactiveAccounts: [],
            visibleInactiveAccountCount: 3,
            visibleInactiveAccountCountOptions: [1, 3, 5],
            refreshIntervalMinutes: 5,
            refreshIntervalOptions: [5, 15, 30],
            statusBarMonochrome: false,
            statusBarIndicatorStyle: .dualArcBadge,
            statusBarDisplayMode: .iconAndText,
            isBusy: false,
            statusMessage: ""
        )
    }
}

private final class ValidationSinkProbe: @unchecked Sendable, MenuBarValidationSink {
    private(set) var snapshots: [MenuBarValidationSnapshot] = []
    private(set) var events: [MenuBarValidationEvent] = []

    func record(_ snapshot: MenuBarValidationSnapshot) throws {
        snapshots.append(snapshot)
    }

    func record(_ event: MenuBarValidationEvent) throws {
        events.append(event)
    }
}
