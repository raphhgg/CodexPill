import AppKit

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

        let claudeCodeUsage = Self.makeClaudeCodeUsage(
            environment: environment,
            defaults: defaults,
            isolatedRootDirectory: isolatedRootDirectory,
            appSupportDirectory: repository.paths.appSupportDirectory
        )
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
            providerConnections: [claudeCodeUsage, cursorUsage],
            allowsEmptyStatePrompt: true
        )
    }

    /// An isolated run never touches the real Claude sign-in: it reads `.credentials.json` from `CLAUDE_CONFIG_DIR`, or
    /// from `.claude` inside the isolated root, skips the Keychain, keeps CodexPill's own sign-in in memory only, and has
    /// no account switching.
    private static func makeClaudeCodeUsage(
        environment: [String: String],
        defaults: UserDefaults,
        isolatedRootDirectory: URL?,
        appSupportDirectory: URL
    ) -> ClaudeCodeUsage {
        let settings = ClaudeUsageSettingsStore(userDefaults: defaults)
        let webClient = URLSessionClaudeUsageWebClient()
        let tokenEndpoint = URLSessionClaudeTokenEndpoint()
        let signInFlow = ClaudeBrowserSignIn(
            tokenEndpoint: tokenEndpoint,
            startReceiver: { try await LoopbackClaudeOAuthReceiver.start() },
            openURL: { url in Task { @MainActor in NSWorkspace.shared.open(url) } }
        )
        if let isolatedRootDirectory {
            let configDirectory = environment["CLAUDE_CONFIG_DIR"]?.isEmpty == false
                ? ClaudeCredentialsSource.configDirectory(environment: environment)
                : isolatedRootDirectory.appendingPathComponent(".claude", isDirectory: true)
            return ClaudeCodeUsage(
                settings: settings,
                client: ClaudeUsageClient(
                    claudeCode: ClaudeCredentialsSource(configDirectory: configDirectory, keychain: nil),
                    signInStore: InMemoryClaudeSignInStore(),
                    tokenEndpoint: tokenEndpoint,
                    webClient: webClient
                ),
                signInFlow: signInFlow
            )
        }

        let configDirectory = ClaudeCredentialsSource.configDirectory(environment: environment)
        let keychain = SystemClaudeKeychain()
        return ClaudeCodeUsage(
            settings: settings,
            client: ClaudeUsageClient(
                claudeCode: ClaudeCredentialsSource(configDirectory: configDirectory, keychain: keychain),
                signInStore: SystemClaudeSignInKeychain(),
                tokenEndpoint: tokenEndpoint,
                webClient: webClient
            ),
            signInFlow: signInFlow,
            accounts: ClaudeCodeAccountStore(
                catalogFile: appSupportDirectory.appendingPathComponent("claude-code-accounts.json"),
                items: SystemClaudeCodeAccountItems(),
                claudeCode: ClaudeCodeSignInStore(
                    configDirectory: configDirectory,
                    globalConfigFile: ClaudeCodeSignInStore.globalConfigFile(
                        environment: environment,
                        homeDirectory: FileManager.default.homeDirectoryForCurrentUser
                    ),
                    keychain: keychain
                ),
                processes: SystemClaudeCodeProcessDetector()
            )
        )
    }

    /// An isolated run never touches the real Cursor: it reads `Cursor/state.vscdb` inside the isolated root and has
    /// no account switching, so it never quits Cursor or writes its database.
    private static func makeCursorUsage(defaults: UserDefaults, isolatedRootDirectory: URL?) -> CursorUsage {
        let settings = CursorUsageSettingsStore(userDefaults: defaults)
        let webClient = URLSessionCursorUsageWebClient()
        if let isolatedRootDirectory {
            return CursorUsage(
                settings: settings,
                client: CursorUsageClient(
                    tokenSource: CursorStateDatabaseTokenSource(databaseURL: CursorStateDatabase.isolatedURL(root: isolatedRootDirectory)),
                    webClient: webClient
                )
            )
        }

        return CursorUsage(
            settings: settings,
            client: CursorUsageClient(tokenSource: CursorStateDatabaseTokenSource(), webClient: webClient),
            accounts: CursorAccounts(
                database: CursorStateDatabase(url: CursorStateDatabase.defaultURL),
                store: SystemCursorAccountKeychain(),
                app: SystemCursorAppProcessClient()
            )
        )
    }
}
