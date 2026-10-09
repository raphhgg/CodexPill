import Foundation

@testable import CodexPill

@MainActor
extension MenuBarCoordinator {
    static func makeForTesting(
        statusItemRuntime: StatusItemRuntime,
        accountsController: MenuBarAccounts,
        settings: SettingsStores,
        remoteHostOperations: MenuBarRemoteHostOperations = UnavailableRemoteHostClient(),
        alertPresenter: AlertPresenter,
        panelPresenter: PanelPresenter = SystemPanelPresenter(suppressesInteractivePrompts: true),
        notificationDelivery: AccountAvailabilityNotifier = DisabledAccountAvailabilityNotifier(),
        applicationActivator: ApplicationActivator = NSApplicationActivator(),
        notificationSettingsLauncher: NotificationSettingsLauncher = SystemNotificationSettingsLauncher(),
        loginItemController: LoginItemControlling = SystemLoginItemController(),
        loginItemsSettingsLauncher: LoginItemsSettingsLaunching = SystemLoginItemsSettingsLauncher(),
        diagnosticReportPresenter: DiagnosticReportPresenting = SystemDiagnosticReportPresenter(),
        tokenUsageProvider: TokenUsageMenuProviding = LocalCodexSessionTokenUsageMenuProvider(
            cacheFile: FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexPillTests-\(ProcessInfo.processInfo.processIdentifier)/Caches/token-usage-cache.json")
        ),
        providerUsageSources: [any UsageProviderSource] = [],
        claudeCodeUsage: ClaudeCodeUsage? = nil,
        cursorUsage: CursorUsage? = nil,
        allowsEmptyStatePrompt: Bool = true,
        autoRefreshIntervalOverride: TimeInterval? = nil
    ) -> MenuBarCoordinator {
        MenuBarCoordinator(
            statusItemRuntime: statusItemRuntime,
            shortcutRuntime: GlobalShortcutRuntime(),
            accountsController: accountsController,
            menuDisplaySettings: settings.menuDisplaySettings,
            statusItemSettings: settings.statusItemSettings,
            remoteHostSettings: settings.remoteHostSettings,
            notificationPreferences: settings.notificationPreferences,
            notificationState: settings.notificationState,
            tokenUsagePreferences: settings.tokenUsagePreferences,
            remoteHostOperations: remoteHostOperations,
            cliProcessInspector: CodexCLIProcessInspector(),
            alertPresenter: alertPresenter,
            panelPresenter: panelPresenter,
            shortcutCapturePanelPresenter: SystemShortcutCapturePanelPresenter(suppressesInteractivePrompts: true),
            notificationDelivery: notificationDelivery,
            applicationActivator: applicationActivator,
            notificationSettingsLauncher: notificationSettingsLauncher,
            loginItemController: loginItemController,
            loginItemsSettingsLauncher: loginItemsSettingsLauncher,
            diagnosticReportPresenter: diagnosticReportPresenter,
            tokenUsageProvider: tokenUsageProvider,
            providerUsageSources: providerUsageSources,
            claudeCodeUsage: claudeCodeUsage,
            cursorUsage: cursorUsage,
            allowsEmptyStatePrompt: allowsEmptyStatePrompt,
            autoRefreshIntervalOverride: autoRefreshIntervalOverride
        )
    }
}
