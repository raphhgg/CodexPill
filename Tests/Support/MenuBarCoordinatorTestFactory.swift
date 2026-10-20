import Foundation

@testable import RUsage

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
                .appendingPathComponent("rusageTests-\(ProcessInfo.processInfo.processIdentifier)/Caches/token-usage-cache.json")
        ),
        providerConnections: [any ProviderConnection] = [],
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
            claudeUsageSettings: settings.claudeUsageSettings,
            themePreferences: settings.themePreferences,
            cliProcessInspector: CodexCLIProcessInspector(),
            alertPresenter: alertPresenter,
            panelPresenter: panelPresenter,
            shortcutCapturePanelPresenter: SystemShortcutCapturePanelPresenter(suppressesInteractivePrompts: true),
            loginItemController: loginItemController,
            loginItemsSettingsLauncher: loginItemsSettingsLauncher,
            diagnosticReportPresenter: diagnosticReportPresenter,
            tokenUsageProvider: tokenUsageProvider,
            providerConnections: providerConnections,
            allowsEmptyStatePrompt: allowsEmptyStatePrompt,
            now: now
        )
    }
}
