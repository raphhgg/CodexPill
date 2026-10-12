import AppKit

@MainActor
final class RefillAppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: MenuBarCoordinator?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? IsolatedCodexHomeSession.cleanupStaleSessions()

        let environment = ProcessInfo.processInfo.environment
        let defaults = AppRuntimeEnvironment.isolatedDefaultsSuiteName(environment: environment)
            .flatMap(UserDefaults.init(suiteName:))
            ?? .standard

        guard AppRuntimeEnvironment.shouldStartAppRuntime(environment: environment) else {
            return
        }

        let composition = AppComposition(environment: environment, defaults: defaults)
        coordinator = composition.coordinator

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.coordinator?.handleSystemDidWake()
            }
        }

        composition.accountsController.load()
        coordinator?.start()
        if let notice = composition.launchNotice {
            coordinator?.presentNotice(notice)
        }
        Task { @MainActor in
            await coordinator?.refreshCodex(includingSavedAccounts: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        coordinator?.invalidate()
    }
}
