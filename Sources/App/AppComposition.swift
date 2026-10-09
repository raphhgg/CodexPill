import Foundation

@MainActor
struct AppComposition {
    let accountsController: AccountsController
    let coordinator: MenuBarCoordinator

    init(environment: [String: String], defaults: UserDefaults, remoteHostSettings: RemoteHostSettingsStore) {
        let isolatedRootDirectory = AppRuntimeEnvironment.isolatedAppSupportDirectory(environment: environment)
        let suppressesInteractivePrompts = AppRuntimeEnvironment.isRunningAutomatedTests(environment: environment)
        let repository = try! AccountRepository(isolatedRootDirectory: isolatedRootDirectory)
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

        let claudeCodeUsage = Self.makeClaudeCodeUsage(environment: environment, isolatedRootDirectory: isolatedRootDirectory)
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
            alertPresenter: SystemAlertPresenter(suppressesInteractivePrompts: suppressesInteractivePrompts),
            panelPresenter: SystemPanelPresenter(suppressesInteractivePrompts: suppressesInteractivePrompts),
            shortcutCapturePanelPresenter: SystemShortcutCapturePanelPresenter(suppressesInteractivePrompts: suppressesInteractivePrompts),
            notificationDelivery: AccountAvailabilityNotificationCenter(),
            applicationActivator: NSApplicationActivator(),
            notificationSettingsLauncher: SystemNotificationSettingsLauncher(),
            loginItemController: SystemLoginItemController(),
            loginItemsSettingsLauncher: SystemLoginItemsSettingsLauncher(),
            diagnosticReportPresenter: SystemDiagnosticReportPresenter(),
            tokenUsageProvider: LocalCodexSessionTokenUsageMenuProvider(
                cacheFile: AppPaths.tokenUsageCacheFile(isolatedRootDirectory: isolatedRootDirectory)
            ),
            providerUsageSources: claudeCodeUsage.map { [$0] } ?? [],
            claudeCodeUsage: claudeCodeUsage,
            allowsEmptyStatePrompt: !AppRuntimeEnvironment.shouldSuppressEmptyStatePrompt(environment: environment),
            autoRefreshIntervalOverride: AppRuntimeEnvironment.validationAutoRefreshIntervalSeconds(environment: environment)
        )
    }

    /// An isolated run never touches the real `~/.claude`: it uses `CLAUDE_CONFIG_DIR` or a folder inside the isolated root.
    private static func makeClaudeCodeUsage(
        environment: [String: String],
        isolatedRootDirectory: URL?
    ) -> ClaudeCodeUsage? {
        guard let relaySourceURL = Bundle.main.url(forResource: "codexpill-claude-usage-relay", withExtension: "sh") else {
            return nil
        }
        let usageFileURL = isolatedRootDirectory?.appendingPathComponent(ClaudeUsageReader.fileName)
            ?? ClaudeUsageReader.defaultFileURL()
        let claudeConfigDirectory: URL
        if let isolatedRootDirectory, environment["CLAUDE_CONFIG_DIR"]?.isEmpty ?? true {
            claudeConfigDirectory = isolatedRootDirectory.appendingPathComponent(".claude", isDirectory: true)
        } else {
            claudeConfigDirectory = ClaudeStatusLineInstaller.defaultClaudeConfigDirectory(environment: environment)
        }
        return ClaudeCodeUsage(
            installer: ClaudeStatusLineInstaller(
                relaySourceURL: relaySourceURL,
                claudeConfigDirectory: claudeConfigDirectory,
                relayInstallURL: usageFileURL.deletingLastPathComponent()
                    .appendingPathComponent("bin", isDirectory: true)
                    .appendingPathComponent(ClaudeStatusLineInstallPlanner.relayFileName)
            ),
            reader: ClaudeUsageReader(fileURL: usageFileURL)
        )
    }
}
