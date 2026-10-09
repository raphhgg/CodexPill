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
        let cursorUsage = Self.makeCursorUsage(environment: environment, defaults: defaults, isolatedRootDirectory: isolatedRootDirectory)
        let providerUsageSources: [any UsageProviderSource] = (claudeCodeUsage.map { [$0] } ?? []) + [cursorUsage]
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
            providerUsageSources: providerUsageSources,
            claudeCodeUsage: claudeCodeUsage,
            cursorUsage: cursorUsage,
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

    /// An isolated run never reads the real Cursor sign-in or calls cursor.com: it reads a fixture database
    /// and a fixture usage summary inside the isolated root.
    private static func makeCursorUsage(
        environment: [String: String],
        defaults: UserDefaults,
        isolatedRootDirectory: URL?
    ) -> CursorUsage {
        let tokenSource: CursorStateDatabaseTokenSource
        let webClient: any CursorUsageWebClient
        if let isolatedRootDirectory {
            tokenSource = CursorStateDatabaseTokenSource(
                databaseURL: isolatedRootDirectory.appendingPathComponent("Cursor/state.vscdb")
            )
            webClient = ValidationCursorUsageWebClient(
                fileURL: isolatedRootDirectory.appendingPathComponent(ValidationCursorUsageWebClient.fileName)
            )
        } else {
            tokenSource = CursorStateDatabaseTokenSource()
            webClient = URLSessionCursorUsageWebClient()
        }
        return CursorUsage(
            settings: CursorUsageSettingsStore(userDefaults: defaults),
            client: CursorUsageClient(tokenSource: tokenSource, webClient: webClient),
            refreshInterval: AppRuntimeEnvironment.validationAutoRefreshIntervalSeconds(environment: environment)
                ?? ProviderUsageRuntime.refreshInterval
        )
    }
}
