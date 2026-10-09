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
        panelPresenter: PanelPresenter = SystemPanelPresenter(),
        notificationDelivery: AccountAvailabilityNotifier = DisabledAccountAvailabilityNotifier(),
        applicationActivator: ApplicationActivator = NSApplicationActivator(),
        notificationSettingsLauncher: NotificationSettingsLauncher = SystemNotificationSettingsLauncher(),
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
            remoteHostSettings: settings.remoteHostSettings,
            notificationPreferences: settings.notificationPreferences,
            notificationState: settings.notificationState,
            tokenUsagePreferences: settings.tokenUsagePreferences,
            remoteHostOperations: remoteHostOperations,
            cliProcessInspector: CodexCLIProcessInspector(),
            alertPresenter: alertPresenter,
            panelPresenter: panelPresenter,
            shortcutCapturePanelPresenter: SystemShortcutCapturePanelPresenter(),
            notificationDelivery: notificationDelivery,
            applicationActivator: applicationActivator,
            notificationSettingsLauncher: notificationSettingsLauncher,
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
