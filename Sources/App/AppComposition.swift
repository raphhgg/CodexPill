import AppKit

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

        let claudeCodeUsage = Self.makeClaudeCodeUsage(environment: environment, defaults: defaults, isolatedRootDirectory: isolatedRootDirectory)
        let cursorUsage = Self.makeCursorUsage(environment: environment, defaults: defaults, isolatedRootDirectory: isolatedRootDirectory)
        let providerUsageSources: [any UsageProviderSource] = [claudeCodeUsage, cursorUsage]
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

    /// An isolated run never reads a real Claude sign-in, opens a browser, or calls Anthropic. Claude Code's sign-in
    /// comes from `CLAUDE_CONFIG_DIR` or a folder inside the isolated root and a fixture file instead of the Keychain.
    /// CodexPill's own sign-in, the token endpoint, the browser callback, and the usage response are fixture files.
    private static func makeClaudeCodeUsage(
        environment: [String: String],
        defaults: UserDefaults,
        isolatedRootDirectory: URL?
    ) -> ClaudeCodeUsage {
        let claudeCode: ClaudeCredentialsSource
        let signInStore: any ClaudeSignInStoring
        let tokenEndpoint: any ClaudeTokenEndpoint
        let webClient: any ClaudeUsageWebClient
        let signInFlow: ClaudeBrowserSignIn
        if let isolatedRootDirectory {
            let configDirectory = environment["CLAUDE_CONFIG_DIR"]?.isEmpty == false
                ? ClaudeCredentialsSource.configDirectory(environment: environment)
                : isolatedRootDirectory.appendingPathComponent(".claude", isDirectory: true)
            claudeCode = ClaudeCredentialsSource(
                configDirectory: configDirectory,
                keychain: ValidationClaudeKeychain(
                    fileURL: isolatedRootDirectory.appendingPathComponent(ValidationClaudeKeychain.fileName)
                )
            )
            signInStore = ValidationClaudeSignInKeychain(
                fileURL: isolatedRootDirectory.appendingPathComponent(ValidationClaudeSignInKeychain.fileName)
            )
            tokenEndpoint = ValidationClaudeTokenEndpoint(
                fileURL: isolatedRootDirectory.appendingPathComponent(ValidationClaudeTokenEndpoint.fileName)
            )
            webClient = ValidationClaudeUsageWebClient(
                fileURL: isolatedRootDirectory.appendingPathComponent(ValidationClaudeUsageWebClient.fileName)
            )
            let receiver = ValidationClaudeRedirectReceiver(rootDirectory: isolatedRootDirectory)
            signInFlow = ClaudeBrowserSignIn(
                tokenEndpoint: tokenEndpoint,
                startReceiver: { receiver },
                openURL: { receiver.recordAuthorizeURL($0) }
            )
        } else {
            claudeCode = ClaudeCredentialsSource(
                configDirectory: ClaudeCredentialsSource.configDirectory(environment: environment),
                keychain: SystemClaudeKeychain()
            )
            signInStore = SystemClaudeSignInKeychain()
            tokenEndpoint = URLSessionClaudeTokenEndpoint()
            webClient = URLSessionClaudeUsageWebClient()
            signInFlow = ClaudeBrowserSignIn(
                tokenEndpoint: tokenEndpoint,
                startReceiver: { try await LoopbackClaudeOAuthReceiver.start() },
                openURL: { url in Task { @MainActor in NSWorkspace.shared.open(url) } }
            )
        }
        return ClaudeCodeUsage(
            settings: ClaudeUsageSettingsStore(userDefaults: defaults),
            client: ClaudeUsageClient(
                claudeCode: claudeCode,
                signInStore: signInStore,
                tokenEndpoint: tokenEndpoint,
                webClient: webClient
            ),
            signInFlow: signInFlow,
            refreshInterval: AppRuntimeEnvironment.validationAutoRefreshIntervalSeconds(environment: environment)
                ?? ProviderUsageRuntime.refreshInterval
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
                databaseURL: CursorStateDatabase.isolatedURL(root: isolatedRootDirectory)
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
