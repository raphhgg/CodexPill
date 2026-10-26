import AppKit
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
        let paths = try! AppPaths(isolatedRootDirectory: isolatedRootDirectory)
        let authFile = CodexAuthFile(url: paths.codexAuthFile)
        let codexAppServerClient = CodexAppServerClient()
        accountsController = AccountsController(
            authFile: authFile,
            accountStatusClient: codexAppServerClient,
            signInWorkflow: CodexSignInWorkflow(authFile: authFile, codexAppProcessClient: SystemCodexAppProcessClient()),
            resetCreditClient: codexAppServerClient
        )

        let settings = SettingsModel(userDefaults: defaults)
        let claudeCodeUsage = Self.makeClaudeCodeUsage(
            environment: environment,
            settings: settings.claude,
            isolatedRootDirectory: isolatedRootDirectory,
            appSupportDirectory: paths.appSupportDirectory
        )
        let cursorUsage = Self.makeCursorUsage(settings: settings.cursor, isolatedRootDirectory: isolatedRootDirectory)
        coordinator = MenuBarCoordinator(
            statusItemRuntime: StatusItemRuntime(),
            shortcutRuntime: GlobalShortcutRuntime(),
            accountsController: accountsController,
            settings: settings,
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

    /// An isolated run never touches the real Claude sign-in: it reads `.credentials.json` from `CLAUDE_CONFIG_DIR`,
    /// or from `.claude` inside the isolated root, and skips the Keychain. rusage's own sign-in then lives in
    /// `claude-sign-in.json` inside the isolated root instead of its Keychain item.
    private static func makeClaudeCodeUsage(
        environment: [String: String],
        settings: SettingsCell<ClaudeSettings>,
        isolatedRootDirectory: URL?,
        appSupportDirectory: URL
    ) -> ClaudeCodeUsage {
        let credentials: ClaudeCredentialsSource
        let signInStore: any ClaudeSignInStoring
        if let isolatedRootDirectory {
            let configDirectory = environment["CLAUDE_CONFIG_DIR"]?.isEmpty == false
                ? ClaudeCredentialsSource.configDirectory(environment: environment)
                : isolatedRootDirectory.appendingPathComponent(".claude", isDirectory: true)
            credentials = ClaudeCredentialsSource(
                configDirectory: configDirectory,
                keychain: nil,
                globalConfigFile: configDirectory.appendingPathComponent(".claude.json")
            )
            signInStore = FileClaudeSignInStore(fileURL: isolatedRootDirectory.appendingPathComponent("claude-sign-in.json"))
        } else {
            credentials = ClaudeCredentialsSource(
                configDirectory: ClaudeCredentialsSource.configDirectory(environment: environment),
                keychain: SystemClaudeKeychain(),
                globalConfigFile: ClaudeCredentialsSource.globalConfigFile(
                    environment: environment,
                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser
                )
            )
            signInStore = SystemClaudeSignInKeychain()
        }

        let tokenEndpoint = URLSessionClaudeTokenEndpoint()
        let ownSignIn = ClaudeOwnSignIn(
            store: signInStore,
            tokenEndpoint: tokenEndpoint,
            lock: ClaudeRefreshLock(fileURL: appSupportDirectory.appendingPathComponent("claude-sign-in.lock"))
        )
        return ClaudeCodeUsage(
            settings: settings,
            client: ClaudeUsageClient(credentials: credentials, ownSignIn: ownSignIn, webClient: URLSessionClaudeUsageWebClient()),
            signInFlow: ClaudeBrowserSignIn(
                tokenEndpoint: tokenEndpoint,
                startReceiver: { try await LoopbackClaudeOAuthReceiver.start() },
                openURL: { url in Task { @MainActor in NSWorkspace.shared.open(url) } }
            )
        )
    }

    /// Codex scans its local sessions. Claude Code adds its local transcripts and Cursor its account's usage
    /// events, each only while that tool is connected. An isolated run reads Codex sessions from `sessions` inside
    /// the isolated root, and Claude transcripts from `CLAUDE_CONFIG_DIR`, or from `.claude` inside the isolated root.
    private static func makeTokenUsageProvider(
        environment: [String: String],
        isolatedRootDirectory: URL?,
        claudeSettings: SettingsCell<ClaudeSettings>,
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
            codex: LocalCodexSessionTokenUsageMenuProvider(
                sessionsDirectory: isolatedRootDirectory?.appendingPathComponent("sessions", isDirectory: true)
                    ?? CodexSessionTokenUsageScanner.defaultSessionsDirectory(),
                cacheFile: cacheFile
            ),
            otherTools: otherTools
        )
    }

    /// An isolated run never reads Cursor's real sign-in: it reads `Cursor/state.vscdb` inside the isolated root, and
    /// keeps rusage's own Cursor sign-in in `cursor-own-sign-in.json` there instead of the Keychain.
    private static func makeCursorUsage(settings: SettingsCell<CursorSettings>, isolatedRootDirectory: URL?) -> CursorUsage {
        let cursorApp = isolatedRootDirectory.map {
            CursorStateDatabaseTokenSource(databaseURL: CursorStateDatabase.isolatedURL(root: $0))
        } ?? CursorStateDatabaseTokenSource()
        let store: any CursorSignInStoring = isolatedRootDirectory.map {
            FileCursorSignInStore(fileURL: $0.appendingPathComponent("cursor-own-sign-in.json"))
        } ?? SystemCursorSignInKeychain()
        let tokenSource = CursorSignInTokenSource(
            usesOwnSignIn: { settings.value.usesOwnSignIn },
            store: store,
            cursorApp: cursorApp
        )
        let webClient = URLSessionCursorUsageWebClient()
        return CursorUsage(
            settings: settings,
            client: CursorUsageClient(tokenSource: tokenSource, webClient: webClient),
            tokenUsageClient: CursorTokenUsageClient(tokenSource: tokenSource, webClient: webClient),
            ownSignInClient: CursorOwnSignIn(store: store, openURL: { url in Task { @MainActor in NSWorkspace.shared.open(url) } }),
            tokenSource: tokenSource
        )
    }
}
