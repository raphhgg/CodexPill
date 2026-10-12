import Foundation

@MainActor
struct AppComposition {
    let accountsController: AccountsController
    let coordinator: MenuBarCoordinator

    init(environment: [String: String], defaults: UserDefaults) {
        let isolatedRootDirectory = AppRuntimeEnvironment.isolatedAppSupportDirectory(environment: environment)
        let suppressesInteractivePrompts = AppRuntimeEnvironment.isRunningAutomatedTests(environment: environment)
        let repository = try! AccountRepository(isolatedRootDirectory: isolatedRootDirectory)
        let authService = CodexAuthSnapshotService(repository: repository)
        let codexAppServerClient = CodexAppServerClient()
        accountsController = AccountsFeatureFactory(
            repository: repository,
            authService: authService,
            codexAppProcessClient: SystemCodexAppProcessClient(),
            accountStatusClient: codexAppServerClient,
            resetCreditClient: codexAppServerClient
        ).makeController()

        let claudeCodeUsage = Self.makeClaudeCodeUsage(environment: environment, defaults: defaults, isolatedRootDirectory: isolatedRootDirectory)
        let cursorUsage = Self.makeCursorUsage(defaults: defaults, isolatedRootDirectory: isolatedRootDirectory)
        coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(),
            shortcutRuntime: GlobalShortcutRuntime(),
            accountsController: accountsController,
            menuDisplaySettings: MenuDisplaySettingsStore(userDefaults: defaults),
            statusItemSettings: StatusItemSettingsStore(userDefaults: defaults),
            tokenUsagePreferences: TokenUsagePreferencesStore(userDefaults: defaults),
            cliProcessInspector: CodexCLIProcessInspector(),
            alertPresenter: SystemAlertPresenter(suppressesInteractivePrompts: suppressesInteractivePrompts),
            panelPresenter: SystemPanelPresenter(suppressesInteractivePrompts: suppressesInteractivePrompts),
            shortcutCapturePanelPresenter: SystemShortcutCapturePanelPresenter(suppressesInteractivePrompts: suppressesInteractivePrompts),
            loginItemController: SystemLoginItemController(),
            loginItemsSettingsLauncher: SystemLoginItemsSettingsLauncher(),
            diagnosticReportPresenter: SystemDiagnosticReportPresenter(),
            tokenUsageProvider: LocalCodexSessionTokenUsageMenuProvider(
                cacheFile: AppPaths.tokenUsageCacheFile(isolatedRootDirectory: isolatedRootDirectory)
            ),
            providerUsageSources: [claudeCodeUsage, cursorUsage],
            claudeCodeUsage: claudeCodeUsage,
            cursorUsage: cursorUsage,
            allowsEmptyStatePrompt: true
        )
    }

    /// An isolated run never reads the real Claude sign-in: it reads `.credentials.json` from `CLAUDE_CONFIG_DIR`, or from
    /// `.claude` inside the isolated root, and skips the Keychain.
    private static func makeClaudeCodeUsage(
        environment: [String: String],
        defaults: UserDefaults,
        isolatedRootDirectory: URL?
    ) -> ClaudeCodeUsage {
        let credentials: ClaudeCredentialsSource
        if let isolatedRootDirectory {
            let configDirectory = environment["CLAUDE_CONFIG_DIR"]?.isEmpty == false
                ? ClaudeCredentialsSource.configDirectory(environment: environment)
                : isolatedRootDirectory.appendingPathComponent(".claude", isDirectory: true)
            credentials = ClaudeCredentialsSource(configDirectory: configDirectory, keychain: nil)
        } else {
            credentials = ClaudeCredentialsSource(
                configDirectory: ClaudeCredentialsSource.configDirectory(environment: environment),
                keychain: SystemClaudeKeychain()
            )
        }
        return ClaudeCodeUsage(
            settings: ClaudeUsageSettingsStore(userDefaults: defaults),
            client: ClaudeUsageClient(credentials: credentials, webClient: URLSessionClaudeUsageWebClient())
        )
    }

    /// An isolated run never reads Cursor's real sign-in: it reads `Cursor/state.vscdb` inside the isolated root.
    private static func makeCursorUsage(defaults: UserDefaults, isolatedRootDirectory: URL?) -> CursorUsage {
        let tokenSource = isolatedRootDirectory.map {
            CursorStateDatabaseTokenSource(databaseURL: CursorStateDatabase.isolatedURL(root: $0))
        } ?? CursorStateDatabaseTokenSource()
        return CursorUsage(
            settings: CursorUsageSettingsStore(userDefaults: defaults),
            client: CursorUsageClient(tokenSource: tokenSource, webClient: URLSessionCursorUsageWebClient())
        )
    }
}
