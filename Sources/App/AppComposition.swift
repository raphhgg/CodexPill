import Foundation

@MainActor
struct AppComposition {
    let accountsController: AccountsController
    let coordinator: MenuBarCoordinator

    init(environment: [String: String], defaults: UserDefaults, remoteHostSettings: RemoteHostSettingsStore) {
        let repository = try! AccountRepository()
        let authService = CodexAuthSnapshotService(repository: repository)
        let processClient: CodexAppProcessClient = AppRuntimeEnvironment.shouldUseValidationCodexProcessClient(environment: environment)
            ? ValidationCodexAppProcessClient()
            : SystemCodexAppProcessClient()
        let remoteHostClient: RemoteHostSwitchWorkflowOperations & MenuBarRemoteHostOperations
        if AppRuntimeEnvironment.shouldUseValidationRemoteHostClient(environment: environment) {
            remoteHostClient = ValidationRemoteHostClient(seedStates: remoteHostSettings.remoteHostStates)
        } else {
            remoteHostClient = SSHRemoteHostClient(snapshotLocator: repository)
        }
        accountsController = AccountsFeatureFactory(
            repository: repository,
            authService: authService,
            codexAppProcessClient: processClient,
            accountStatusClient: CodexAppServerClient(),
            remoteHostSwitchOperations: remoteHostClient
        ).makeController()

        coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(),
            shortcutRuntime: GlobalShortcutRuntime(),
            accountsController: accountsController,
            menuDisplaySettings: MenuDisplaySettingsStore(userDefaults: defaults),
            statusItemSettings: StatusItemSettingsStore(userDefaults: defaults),
            remoteHostSettings: remoteHostSettings,
            notificationPreferences: NotificationPreferencesStore(userDefaults: defaults),
            notificationState: NotificationStateStore(userDefaults: defaults),
            tokenUsagePreferences: TokenUsagePreferencesStore(userDefaults: defaults),
            remoteHostOperations: remoteHostClient,
            cliProcessInspector: CodexCLIProcessInspector(),
            alertPresenter: SystemAlertPresenter(environment: environment),
            panelPresenter: SystemPanelPresenter(environment: environment),
            shortcutCapturePanelPresenter: SystemShortcutCapturePanelPresenter(environment: environment),
            notificationDelivery: AccountAvailabilityNotificationCenter(),
            applicationActivator: NSApplicationActivator(),
            notificationSettingsLauncher: SystemNotificationSettingsLauncher(),
            loginItemController: SystemLoginItemController(),
            loginItemsSettingsLauncher: SystemLoginItemsSettingsLauncher(),
            diagnosticReportPresenter: SystemDiagnosticReportPresenter(),
            tokenUsageProvider: LocalCodexSessionTokenUsageMenuProvider(),
            validationObserver: MenuBarValidationObserver(
                sink: MenuBarValidationConfiguration.makeSink(environment: environment),
                scenario: MenuBarValidationConfiguration.scenario(environment: environment)
            ),
            allowsEmptyStatePrompt: !AppRuntimeEnvironment.shouldSuppressEmptyStatePrompt(environment: environment),
            autoRefreshIntervalOverride: AppRuntimeEnvironment.validationAutoRefreshIntervalSeconds(environment: environment)
        )
    }
}
