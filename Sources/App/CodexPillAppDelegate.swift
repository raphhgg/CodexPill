import AppKit
import UserNotifications

@MainActor
final class CodexPillAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var coordinator: MenuBarCoordinator?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? IsolatedCodexHomeSession.cleanupStaleSessions()

        let environment = ProcessInfo.processInfo.environment
        let defaults = AppRuntimeEnvironment.validationUserDefaultsSuiteName(environment: environment)
            .flatMap(UserDefaults.init(suiteName:))
            ?? .standard
        let remoteHostSettings = RemoteHostSettingsStore(userDefaults: defaults)
        ValidationAppBootstrap.applyFixtureIfPresent(to: remoteHostSettings, environment: environment)

        guard AppRuntimeEnvironment.shouldStartAppRuntime(environment: environment) else {
            return
        }

        let composition = AppComposition(
            environment: environment,
            defaults: defaults,
            remoteHostSettings: remoteHostSettings
        )
        let accountsController = composition.accountsController
        coordinator = composition.coordinator

        UNUserNotificationCenter.current().delegate = self

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.coordinator?.handleSystemDidWake()
            }
        }

        accountsController.load()
        coordinator?.start()
        Task { @MainActor in
            if let activeAccount = accountsController.activeAccount {
                _ = await accountsController.refreshAccountData(for: activeAccount)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        coordinator?.invalidate()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = AccountAvailabilityNotificationResponsePayload(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        )
        await coordinator?.handleNotificationResponse(payload)
    }

}
