import AppKit
import UserNotifications

enum AccountAvailabilityNotificationActionKind: Equatable {
    case local
    case remote(hostDestination: String)
    case bestOption
}

struct AccountAvailabilityNotificationAction: Equatable {
    let identifier: String
    let title: String
    let kind: AccountAvailabilityNotificationActionKind
}

struct AccountAvailabilityNotificationPayload: Equatable {
    let accountID: UUID
    let title: String
    let body: String
    let actions: [AccountAvailabilityNotificationAction]
}

struct AccountAvailabilityNotificationResponsePayload: Sendable {
    let actionIdentifier: String?
    let accountIDString: String?
    let remoteHostDestination: String?

    init(actionIdentifier: String?, userInfo: [AnyHashable: Any]) {
        self.actionIdentifier = actionIdentifier
        self.accountIDString = userInfo["accountID"] as? String
        self.remoteHostDestination = userInfo["remoteHostDestination"] as? String
    }
}

struct AccountAvailabilityNotificationCopyRenderer {
    func render(
        decision: AccountAvailabilityNotificationDecision,
        remoteHosts: [RemoteHostMenuState]
    ) -> (title: String, body: String) {
        switch decision.reason {
        case .whenBlocked:
            return ("CodexPill", "\(decision.account.name) is available again")
        case .whenOut:
            guard let triggerContext = decision.triggerContext else {
                return ("CodexPill", "\(decision.account.name) is available again")
            }

            return (
                "\(triggerContext.accountName) is out on \(targetLabel(for: triggerContext.target, remoteHosts: remoteHosts))",
                "\(limitSummary(for: triggerContext)). \(decision.account.name) is ready."
            )
        }
    }

    private func targetLabel(
        for target: AccountAvailabilityTarget,
        remoteHosts: [RemoteHostMenuState]
    ) -> String {
        switch target {
        case .local:
            return "This Mac"
        case .remote(let hostDestination):
            return remoteHosts.first(where: { $0.destination == hostDestination })?.name ?? hostDestination
        }
    }

    private func limitSummary(
        for triggerContext: AccountAvailabilityNotificationTriggerContext
    ) -> String {
        let sessionOut = triggerContext.sessionRemainingPercent <= 0
        let weeklyOut = triggerContext.weeklyRemainingPercent <= 0

        switch (sessionOut, weeklyOut) {
        case (true, true):
            return "Session and weekly limits reached"
        case (true, false):
            return "Session limit reached"
        case (false, true):
            return "Weekly limit reached"
        case (false, false):
            return "Limit reached"
        }
    }
}

@MainActor
protocol AccountAvailabilityNotifier {
    func authorizationState() async -> NotificationAuthorizationState
    func requestAuthorizationIfNeeded() async
    func deliver(_ payload: AccountAvailabilityNotificationPayload) async -> Bool
}

protocol NotificationSettingsLauncher {
    func openNotificationSettings()
}

@MainActor
protocol UserNotificationCenterClient: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
}

extension UNUserNotificationCenter: UserNotificationCenterClient {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

struct SystemNotificationSettingsLauncher: NotificationSettingsLauncher {
    func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

final class AccountAvailabilityNotificationCenter: AccountAvailabilityNotifier {
    private let center: UserNotificationCenterClient
    private var hasRequestedAuthorization = false

    init(center: UserNotificationCenterClient = UNUserNotificationCenter.current()) {
        self.center = center
    }

    func authorizationState() async -> NotificationAuthorizationState {
        switch await center.authorizationStatus() {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unknown
        }
    }

    func requestAuthorizationIfNeeded() async {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func deliver(_ payload: AccountAvailabilityNotificationPayload) async -> Bool {
        let rendered = renderedActions(for: payload.actions)
        if let category = rendered.category {
            center.setNotificationCategories([category])
        }

        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        if let categoryIdentifier = rendered.category?.identifier {
            content.categoryIdentifier = categoryIdentifier
        }
        content.userInfo = userInfo(for: payload, renderedActions: rendered.actions)

        let request = UNNotificationRequest(
            identifier: "account-availability-\(payload.accountID.uuidString)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    private func renderedActions(
        for actions: [AccountAvailabilityNotificationAction]
    ) -> (actions: [AccountAvailabilityNotificationAction], category: UNNotificationCategory?) {
        guard !actions.isEmpty else {
            return (actions: [], category: nil)
        }

        let directActions = actions.filter {
            if case .bestOption = $0.kind {
                return false
            }
            return true
        }

        let finalActions: [AccountAvailabilityNotificationAction]
        if !directActions.isEmpty, directActions.count <= 2 {
            finalActions = directActions
        } else {
            finalActions = [AccountAvailabilityNotificationAction(
                identifier: "use_best_option",
                title: "Use Best Option",
                kind: .bestOption
            )]
        }

        guard !finalActions.isEmpty else {
            return (actions: [], category: nil)
        }

        let categoryActions = finalActions.map {
            UNNotificationAction(identifier: $0.identifier, title: $0.title)
        }
        let categoryIdentifier = "account_availability_\(finalActions.map(\.identifier).joined(separator: "_"))"
        return (
            actions: finalActions,
            category: UNNotificationCategory(
                identifier: categoryIdentifier,
                actions: categoryActions,
                intentIdentifiers: [],
                options: []
            )
        )
    }

    private func userInfo(
        for payload: AccountAvailabilityNotificationPayload,
        renderedActions: [AccountAvailabilityNotificationAction]
    ) -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = [
            "accountID": payload.accountID.uuidString
        ]

        if let remoteAction = renderedActions.first(where: {
            if case .remote = $0.kind {
                return true
            }
            return false
        }),
           case .remote(let hostDestination) = remoteAction.kind {
            userInfo["remoteHostDestination"] = hostDestination
        }

        return userInfo
    }
}

final class DisabledAccountAvailabilityNotifier: AccountAvailabilityNotifier {
    func authorizationState() async -> NotificationAuthorizationState {
        .unknown
    }

    func requestAuthorizationIfNeeded() async {}

    func deliver(_ payload: AccountAvailabilityNotificationPayload) async -> Bool {
        false
    }
}

struct AccountAvailabilityNotificationPayloadRenderer {
    private let copyRenderer = AccountAvailabilityNotificationCopyRenderer()

    func payload(
        for decision: AccountAvailabilityNotificationDecision,
        state: MenuBarMenuState
    ) -> AccountAvailabilityNotificationPayload? {
        let actions = decision.suggestedActions.compactMap { suggestion -> AccountAvailabilityNotificationAction? in
            switch suggestion {
            case .local:
                return AccountAvailabilityNotificationAction(
                    identifier: "use_local",
                    title: "Use on This Mac",
                    kind: .local
                )
            case .remote(let hostDestination):
                let hostName = state.resolvedRemoteHosts.first(where: { $0.destination == hostDestination })?.name ?? hostDestination
                return AccountAvailabilityNotificationAction(
                    identifier: "use_remote",
                    title: "Use on \(hostName)",
                    kind: .remote(hostDestination: hostDestination)
                )
            }
        }

        let renderedCopy = copyRenderer.render(
            decision: decision,
            remoteHosts: state.resolvedRemoteHosts
        )

        return AccountAvailabilityNotificationPayload(
            accountID: decision.account.id,
            title: renderedCopy.title,
            body: renderedCopy.body,
            actions: actions
        )
    }
}
