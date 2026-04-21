import AppKit

@MainActor
final class CodexPillAppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: MenuBarCoordinator!
    private var settings: AppSettings!
    private var statusItemRuntime: StatusItemRuntime!
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        let defaults = AppRuntimeEnvironment.validationUserDefaultsSuiteName(environment: environment)
            .flatMap(UserDefaults.init(suiteName:))
            ?? .standard
        settings = AppSettings(userDefaults: defaults)
        ValidationAppBootstrap.applyFixtureIfPresent(to: settings, environment: environment)

        let repository = try! AccountRepository()
        let authService = CodexAuthSnapshotService(repository: repository)
        let controller = CodexAppController()
        let appServerClient = CodexAppServerClient()
        let remoteHostClient: RemoteHostSwitching
        if AppRuntimeEnvironment.shouldUseValidationRemoteHostClient(environment: environment) {
            remoteHostClient = ValidationRemoteHostClient(seedStates: settings.remoteHostStates)
        } else {
            remoteHostClient = SSHRemoteHostClient(snapshotLocator: repository)
        }
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: authService,
            appController: controller,
            appServerClient: appServerClient,
            remoteHostClient: remoteHostClient
        )

        statusItemRuntime = StatusItemRuntime()
        coordinator = MenuBarCoordinator(
            statusItemRuntime: statusItemRuntime,
            store: store,
            settings: settings,
            remoteHostClient: remoteHostClient,
            alertPresenter: MenuBarAlertPresenter(),
            validationSink: MenuBarValidationConfiguration.makeSink(),
            allowsEmptyStatePrompt: !AppRuntimeEnvironment.shouldSuppressEmptyStatePrompt()
        )

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.coordinator.handleSystemDidWake()
            }
        }

        store.load()
        coordinator.start()
        Task { @MainActor in
            if let activeAccount = store.activeAccount {
                _ = await store.refreshAccountData(for: activeAccount)
            }
            await store.hydrateSavedAccountsMetadataIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        coordinator.invalidate()
    }
}
