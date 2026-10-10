import Foundation

@testable import CodexPill

@MainActor
extension MenuBarCoordinator {
    static func makeForTesting(
        statusItemRuntime: StatusItemRuntime,
        accountsController: MenuBarAccounts,
        settings: SettingsStores,
        alertPresenter: AlertPresenter,
        panelPresenter: PanelPresenter = SystemPanelPresenter(suppressesInteractivePrompts: true),
        loginItemController: LoginItemControlling = SystemLoginItemController(),
        loginItemsSettingsLauncher: LoginItemsSettingsLaunching = SystemLoginItemsSettingsLauncher(),
        diagnosticReportPresenter: DiagnosticReportPresenting = SystemDiagnosticReportPresenter(),
        tokenUsageProvider: TokenUsageMenuProviding = LocalCodexSessionTokenUsageMenuProvider(
            cacheFile: FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexPillTests-\(ProcessInfo.processInfo.processIdentifier)/Caches/token-usage-cache.json")
        ),
        providerUsageSources: [any UsageProviderSource] = [],
        allowsEmptyStatePrompt: Bool = true,
        now: @escaping () -> Date = Date.init
    ) -> MenuBarCoordinator {
        MenuBarCoordinator(
            statusItemRuntime: statusItemRuntime,
            shortcutRuntime: GlobalShortcutRuntime(),
            accountsController: accountsController,
            menuDisplaySettings: settings.menuDisplaySettings,
            statusItemSettings: settings.statusItemSettings,
            tokenUsagePreferences: settings.tokenUsagePreferences,
            cliProcessInspector: CodexCLIProcessInspector(),
            alertPresenter: alertPresenter,
            panelPresenter: panelPresenter,
            shortcutCapturePanelPresenter: SystemShortcutCapturePanelPresenter(suppressesInteractivePrompts: true),
            loginItemController: loginItemController,
            loginItemsSettingsLauncher: loginItemsSettingsLauncher,
            diagnosticReportPresenter: diagnosticReportPresenter,
            tokenUsageProvider: tokenUsageProvider,
            providerUsageSources: providerUsageSources,
            allowsEmptyStatePrompt: allowsEmptyStatePrompt,
            now: now
        )
    }
}
