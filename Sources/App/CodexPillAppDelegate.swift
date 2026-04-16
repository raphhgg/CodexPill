import AppKit

@MainActor
final class CodexPillAppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: MenuBarCoordinator!
    private let settings = AppSettings()
    private var statusItem: NSStatusItem!
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let repository = try! AccountRepository()
        let authService = CodexAuthSnapshotService(repository: repository)
        let controller = CodexAppController()
        let appServerClient = CodexAppServerClient()
        let store = MenuBarAccountsStore(
            repository: repository,
            authService: authService,
            appController: controller,
            appServerClient: appServerClient
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        coordinator = MenuBarCoordinator(
            statusItem: statusItem,
            store: store,
            settings: settings,
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
                await store.refreshAccountData(for: activeAccount)
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
