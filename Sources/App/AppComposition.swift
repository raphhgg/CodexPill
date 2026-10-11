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

    /// An isolated run never touches the real Claude sign-in or the real `claude`: it reads `.credentials.json` from
    /// `CLAUDE_CONFIG_DIR`, or from `.claude` inside the isolated root, skips the Keychain, keeps saved accounts as
    /// files in the isolated root, and runs only a `claude` placed in `bin` inside the isolated root.
    private static func makeClaudeCodeUsage(
        environment: [String: String],
        defaults: UserDefaults,
        isolatedRootDirectory: URL?,
        appSupportDirectory: URL
    ) -> ClaudeCodeUsage {
        let settings = ClaudeUsageSettingsStore(userDefaults: defaults)
        let webClient = URLSessionClaudeUsageWebClient()
        let catalogFile = (isolatedRootDirectory ?? appSupportDirectory).appendingPathComponent("claude-code-accounts.json")
        let commandsRoot = (isolatedRootDirectory ?? appSupportDirectory).appendingPathComponent("claude-sign-in", isDirectory: true)
        let hasConfigDirectoryOverride = environment["CLAUDE_CONFIG_DIR"]?.isEmpty == false

        if let isolatedRootDirectory {
            let configDirectory = hasConfigDirectoryOverride
                ? ClaudeCredentialsSource.configDirectory(environment: environment)
                : isolatedRootDirectory.appendingPathComponent(".claude", isDirectory: true)
            return ClaudeCodeUsage(
                settings: settings,
                client: ClaudeUsageClient(
                    credentials: ClaudeCredentialsSource(
                        configDirectory: configDirectory,
                        keychain: nil,
                        globalConfigFile: configDirectory.appendingPathComponent(".claude.json")
                    ),
                    webClient: webClient
                ),
                accounts: ClaudeCodeAccountStore(
                    catalogFile: catalogFile,
                    items: IsolatedClaudeCodeAccountItems(
                        directory: isolatedRootDirectory.appendingPathComponent("claude-code-accounts", isDirectory: true)
                    ),
                    claudeCode: ClaudeCodeSignInStore(
                        configDirectory: configDirectory,
                        globalConfigFile: configDirectory.appendingPathComponent(".claude.json"),
                        keychain: nil
                    ),
                    processes: SystemClaudeCodeProcessDetector()
                ),
                commands: ClaudeCodeCommands(
                    processes: SystemClaudeCodeProcessRunner(
                        searchDirectories: [isolatedRootDirectory.appendingPathComponent("bin", isDirectory: true)]
                    ),
                    keychain: SystemClaudeCodeFolderKeychain(),
                    root: commandsRoot
                ),
                liveConfigDirectory: configDirectory.path
            )
        }

        let configDirectory = ClaudeCredentialsSource.configDirectory(environment: environment)
        let globalConfigFile = ClaudeCodeSignInStore.globalConfigFile(
            environment: environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        let keychain = SystemClaudeKeychain()
        let commands = ClaudeCodeCommands(
            processes: SystemClaudeCodeProcessRunner(),
            keychain: SystemClaudeCodeFolderKeychain(),
            root: commandsRoot
        )
        Task.detached { commands.removeLeftovers() }
        return ClaudeCodeUsage(
            settings: settings,
            client: ClaudeUsageClient(
                credentials: ClaudeCredentialsSource(configDirectory: configDirectory, keychain: keychain, globalConfigFile: globalConfigFile),
                webClient: webClient
            ),
            accounts: ClaudeCodeAccountStore(
                catalogFile: catalogFile,
                items: SystemClaudeCodeAccountItems(),
                claudeCode: ClaudeCodeSignInStore(
                    configDirectory: configDirectory,
                    globalConfigFile: globalConfigFile,
                    keychain: keychain
                ),
                processes: SystemClaudeCodeProcessDetector()
            ),
            commands: commands,
            liveConfigDirectory: hasConfigDirectoryOverride ? environment["CLAUDE_CONFIG_DIR"] : nil
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
