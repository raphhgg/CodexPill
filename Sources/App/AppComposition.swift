import Foundation

@MainActor
struct AppComposition {
    let accountsController: AccountsController
    let coordinator: MenuBarCoordinator
    /// Shown once after launch when CodexPill's data did not fully carry over.
    let launchNotice: MenuBarInfoAlertRequest?

    init(environment: [String: String], defaults: UserDefaults) {
        let isolatedRootDirectory = AppRuntimeEnvironment.isolatedAppSupportDirectory(environment: environment)
        let isIsolated = isolatedRootDirectory != nil || AppRuntimeEnvironment.isolatedDefaultsSuiteName(environment: environment) != nil
        launchNotice = isIsolated ? nil : Self.migrateCodexPillData(defaults: defaults)
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
            claudeUsageSettings: claudeCodeUsage.settings,
            themePreferences: ThemePreferencesStore(userDefaults: defaults),
            appIconApplier: SystemAppIconApplier(),
            cliProcessInspector: CodexCLIProcessInspector(),
            alertPresenter: SystemAlertPresenter(suppressesInteractivePrompts: suppressesInteractivePrompts),
            panelPresenter: SystemPanelPresenter(suppressesInteractivePrompts: suppressesInteractivePrompts),
            shortcutCapturePanelPresenter: SystemShortcutCapturePanelPresenter(suppressesInteractivePrompts: suppressesInteractivePrompts),
            loginItemController: SystemLoginItemController(),
            loginItemsSettingsLauncher: SystemLoginItemsSettingsLauncher(),
            diagnosticReportPresenter: SystemDiagnosticReportPresenter(),
            tokenUsageProvider: Self.makeTokenUsageProvider(
                environment: environment,
                isolatedRootDirectory: isolatedRootDirectory,
                claudeSettings: claudeCodeUsage.settings,
                cursorUsage: cursorUsage
            ),
            providerConnections: [claudeCodeUsage, cursorUsage],
            allowsEmptyStatePrompt: true
        )
    }

    /// Runs before anything reads the catalog or the settings, so the first read already sees CodexPill's data.
    private static func migrateCodexPillData(defaults: UserDefaults) -> MenuBarInfoAlertRequest? {
        let outcome = (try? CodexPillMigration.live(defaults: defaults, bundleIdentifier: Bundle.main.bundleIdentifier))?.run() ?? .failed
        guard outcome == .failed else { return nil }
        return MenuBarAlertFactory().makeCodexPillDataNotCopiedRequest()
    }

    /// An isolated run never touches the real Claude sign-in or the real `claude`: it reads `.credentials.json` from
    /// `CLAUDE_CONFIG_DIR`, or from `.claude` inside the isolated root, skips the Keychain, and runs only a `claude`
    /// placed in `bin` inside the isolated root.
    private static func makeClaudeCodeUsage(
        environment: [String: String],
        defaults: UserDefaults,
        isolatedRootDirectory: URL?
    ) -> ClaudeCodeUsage {
        let settings = ClaudeUsageSettingsStore(userDefaults: defaults)
        let webClient = URLSessionClaudeUsageWebClient()
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
                commands: ClaudeCodeCommands(
                    processes: SystemClaudeCodeProcessRunner(
                        searchDirectories: [isolatedRootDirectory.appendingPathComponent("bin", isDirectory: true)]
                    )
                ),
                processes: SystemClaudeCodeProcessDetector(),
                liveConfigDirectory: configDirectory.path
            )
        }

        let configDirectory = ClaudeCredentialsSource.configDirectory(environment: environment)
        return ClaudeCodeUsage(
            settings: settings,
            client: ClaudeUsageClient(
                credentials: ClaudeCredentialsSource(
                    configDirectory: configDirectory,
                    keychain: SystemClaudeKeychain(),
                    globalConfigFile: ClaudeCredentialsSource.globalConfigFile(
                        environment: environment,
                        homeDirectory: FileManager.default.homeDirectoryForCurrentUser
                    )
                ),
                webClient: webClient
            ),
            commands: ClaudeCodeCommands(processes: SystemClaudeCodeProcessRunner()),
            processes: SystemClaudeCodeProcessDetector(),
            liveConfigDirectory: hasConfigDirectoryOverride ? environment["CLAUDE_CONFIG_DIR"] : nil
        )
    }

    /// Codex scans its local sessions. Claude Code adds its local transcripts and Cursor its account's usage
    /// events, each only while that tool is connected. An isolated run reads Claude transcripts from
    /// `CLAUDE_CONFIG_DIR`, or from `.claude` inside the isolated root.
    private static func makeTokenUsageProvider(
        environment: [String: String],
        isolatedRootDirectory: URL?,
        claudeSettings: ClaudeUsageSettingsStore,
        cursorUsage: CursorUsage
    ) -> any TokenUsageMenuProviding {
        let cacheFile = AppPaths.tokenUsageCacheFile(isolatedRootDirectory: isolatedRootDirectory)
        let claudeConfigDirectory = isolatedRootDirectory != nil && environment["CLAUDE_CONFIG_DIR"]?.isEmpty != false
            ? isolatedRootDirectory!.appendingPathComponent(".claude", isDirectory: true)
            : ClaudeCredentialsSource.configDirectory(environment: environment)
        let claudeHistory = ClaudeCodeTokenUsageHistory(
            projectsDirectory: claudeConfigDirectory.appendingPathComponent("projects", isDirectory: true),
            cacheFile: cacheFile.deletingLastPathComponent().appendingPathComponent("claude-token-usage-cache.json")
        )
        var otherTools: [TokenUsageToolSource] = [.claudeCode(history: claudeHistory, settings: claudeSettings)]
        if let cursorClient = cursorUsage.tokenUsageClient {
            otherTools.append(.cursor(client: cursorClient, settings: cursorUsage.settings))
        }
        return AllToolsTokenUsageMenuProvider(
            codex: LocalCodexSessionTokenUsageMenuProvider(cacheFile: cacheFile),
            otherTools: otherTools
        )
    }

    /// An isolated run never reads Cursor's real sign-in: it reads `Cursor/state.vscdb` inside the isolated root.
    private static func makeCursorUsage(defaults: UserDefaults, isolatedRootDirectory: URL?) -> CursorUsage {
        let tokenSource = isolatedRootDirectory.map {
            CursorStateDatabaseTokenSource(databaseURL: CursorStateDatabase.isolatedURL(root: $0))
        } ?? CursorStateDatabaseTokenSource()
        let webClient = URLSessionCursorUsageWebClient()
        return CursorUsage(
            settings: CursorUsageSettingsStore(userDefaults: defaults),
            client: CursorUsageClient(tokenSource: tokenSource, webClient: webClient),
            tokenUsageClient: CursorTokenUsageClient(tokenSource: tokenSource, webClient: webClient)
        )
    }
}
