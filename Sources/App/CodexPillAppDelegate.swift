import AppKit

@MainActor
final class CodexPillAppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: MenuBarCoordinator?
    private var statusItemRuntime: StatusItemRuntime?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? IsolatedCodexHomeSession.cleanupStaleSessions()

        let environment = ProcessInfo.processInfo.environment
        let defaults = AppRuntimeEnvironment.validationUserDefaultsSuiteName(environment: environment)
            .flatMap(UserDefaults.init(suiteName:))
            ?? .standard

        guard AppRuntimeEnvironment.shouldStartAppRuntime(environment: environment) else {
            return
        }

        let repository = try! AccountRepository()
        let authService = CodexAuthSnapshotService(repository: repository)
        let processClient: CodexAppProcessClient = AppRuntimeEnvironment.shouldUseValidationCodexProcessClient(environment: environment)
            ? ValidationCodexAppProcessClient()
            : SystemCodexAppProcessClient()
        let accountStatusClient = CodexAppServerClient()
        let accountsFeatureFactory = AccountsFeatureFactory(
            repository: repository,
            authService: authService,
            codexAppProcessClient: processClient,
            accountStatusClient: accountStatusClient
        )
        let accountsController = accountsFeatureFactory.makeController()

        let statusItemRuntime = StatusItemRuntime()
        self.statusItemRuntime = statusItemRuntime
        coordinator = MenuBarCoordinator(
            statusItemRuntime: statusItemRuntime,
            accountsController: accountsController,
            menuDisplaySettings: MenuDisplaySettingsStore(userDefaults: defaults),
            statusItemSettings: StatusItemSettingsStore(userDefaults: defaults),
            tokenUsagePreferences: TokenUsagePreferencesStore(userDefaults: defaults),
            alertPresenter: SystemAlertPresenter(),
            validationSink: MenuBarValidationConfiguration.makeSink(),
            allowsEmptyStatePrompt: !AppRuntimeEnvironment.shouldSuppressEmptyStatePrompt()
        )

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
}
