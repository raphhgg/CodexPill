import Foundation

@testable import CodexPill

@MainActor
extension MenuBarCoordinator {
    static func makeForTesting(
        statusItemRuntime: StatusItemRuntime,
        accountsController: MenuBarAccounts,
        settings: SettingsStores,
        alertPresenter: AlertPresenter,
        panelPresenter: PanelPresenter = SystemPanelPresenter(),
        loginItemController: LoginItemControlling = SystemLoginItemController(),
        loginItemsSettingsLauncher: LoginItemsSettingsLaunching = SystemLoginItemsSettingsLauncher(),
        diagnosticReportPresenter: DiagnosticReportPresenting = SystemDiagnosticReportPresenter(),
        tokenUsageProvider: TokenUsageMenuProviding = LocalCodexSessionTokenUsageMenuProvider(),
        validationSink: MenuBarValidationSink? = nil,
        validationScenario: String? = MenuBarValidationConfiguration.scenario(),
        allowsEmptyStatePrompt: Bool = true,
        autoRefreshIntervalOverride: TimeInterval? = nil
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
            shortcutCapturePanelPresenter: SystemShortcutCapturePanelPresenter(),
            loginItemController: loginItemController,
            loginItemsSettingsLauncher: loginItemsSettingsLauncher,
            diagnosticReportPresenter: diagnosticReportPresenter,
            tokenUsageProvider: tokenUsageProvider,
            validationObserver: MenuBarValidationObserver(sink: validationSink, scenario: validationScenario),
            allowsEmptyStatePrompt: allowsEmptyStatePrompt,
            autoRefreshIntervalOverride: autoRefreshIntervalOverride
        )
    }
}
