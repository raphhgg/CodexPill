import AppKit
import UserNotifications

@MainActor
final class CodexPillAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var coordinator: MenuBarCoordinator?
    private var settings: CodexPillSettingsStore!
    private var statusItemRuntime: StatusItemRuntime?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? IsolatedCodexHomeSession.cleanupStaleSessions()

        let environment = ProcessInfo.processInfo.environment
        let defaults = AppRuntimeEnvironment.validationUserDefaultsSuiteName(environment: environment)
            .flatMap(UserDefaults.init(suiteName:))
            ?? .standard
        settings = CodexPillSettingsStore(userDefaults: defaults)
        ValidationAppBootstrap.applyFixtureIfPresent(to: settings, environment: environment)

        guard AppRuntimeEnvironment.shouldStartAppRuntime(environment: environment) else {
            return
        }

        let repository = try! AccountRepository()
        let authService = CodexAuthSnapshotService(repository: repository)
        let processClient: CodexAppProcessClient = AppRuntimeEnvironment.shouldUseValidationCodexProcessClient(environment: environment)
            ? ValidationCodexAppProcessClient()
            : SystemCodexAppProcessClient()
        let accountStatusClient = CodexAppServerClient()
        let remoteHostClient: RemoteHostSwitchWorkflowOperations
            & RemoteHostAccountSigningOut
        if AppRuntimeEnvironment.shouldUseValidationRemoteHostClient(environment: environment) {
            remoteHostClient = ValidationRemoteHostClient(seedStates: settings.remoteHostStates)
        } else {
            remoteHostClient = SSHRemoteHostClient(snapshotLocator: repository)
        }
        let accountsFeatureFactory = AccountsFeatureFactory(
            repository: repository,
            authService: authService,
            codexAppProcessClient: processClient,
            accountStatusClient: accountStatusClient,
            remoteHostSwitchOperations: remoteHostClient
        )
        let store = accountsFeatureFactory.makeMenuBarAccountsStore()

        let statusItemRuntime = StatusItemRuntime()
        self.statusItemRuntime = statusItemRuntime
        coordinator = MenuBarCoordinator(
            statusItemRuntime: statusItemRuntime,
            store: store,
            settings: settings,
            remoteHostConnectionChecker: remoteHostClient,
            remoteHostAccountStatusReader: remoteHostClient,
            remoteHostAccountSignerOut: remoteHostClient,
            remoteHostAppServerRefresher: remoteHostClient,
            alertPresenter: SystemAlertPresenter(),
            validationSink: MenuBarValidationConfiguration.makeSink(),
            allowsEmptyStatePrompt: !AppRuntimeEnvironment.shouldSuppressEmptyStatePrompt()
        )

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

        store.load()
        coordinator?.start()
        Task { @MainActor in
            if let activeAccount = store.activeAccount {
                _ = await store.refreshAccountData(for: activeAccount)
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
