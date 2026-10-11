import AppKit

struct MenuBarMenuState {
    let activeAccount: CodexAccount?
    /// Ranked by room left, best first.
    let inactiveAccounts: [CodexAccount]
    let refreshIntervalMinutes: Int
    let refreshIntervalOptions: [Int]
    let statusBarIndicatorStyle: StatusBarIndicatorStyle
    let statusBarDisplayMode: StatusBarDisplayMode
    let revealStatusItemTitleShortcut: KeyboardShortcut?
    let sessionAccentColor: NSColor
    let weeklyAccentColor: NSColor
    let usesOneUsageColor: Bool
    let hasCustomUsageColors: Bool
    let usagePercentMode: UsagePercentMode
    let usageMeterLayout: UsageMeterLayout
    let pacingMarkersEnabled: Bool
    let isBusy: Bool
    let statusMessage: String
    let loginItemState: LoginItemState
    let tokenUsageEnabled: Bool
    let tokenUsageCard: TokenUsageMenuCard?
    let providerUsage: [ProviderUsageState]
    let toolOrder: [UsageProvider]
    let masksEmails: Bool
    let showsModelLimits: Bool
    let appIconColor: AppIconColor
    /// The moment reset countdowns and elapsed times in the menu are measured from.
    let now: Date

    init(
        activeAccount: CodexAccount?,
        inactiveAccounts: [CodexAccount],
        refreshIntervalMinutes: Int = 5,
        refreshIntervalOptions: [Int] = [1, 2, 5, 10, 15, 30],
        statusBarIndicatorStyle: StatusBarIndicatorStyle = .hourglass,
        statusBarDisplayMode: StatusBarDisplayMode = .iconOnly,
        revealStatusItemTitleShortcut: KeyboardShortcut? = .defaultRevealStatusItemTitle,
        sessionAccentColor: NSColor = StatusBarProgressColorDefaults.accent,
        weeklyAccentColor: NSColor = StatusBarProgressColorDefaults.accent,
        usesOneUsageColor: Bool = true,
        hasCustomUsageColors: Bool = false,
        usagePercentMode: UsagePercentMode = .used,
        usageMeterLayout: UsageMeterLayout = .classic,
        pacingMarkersEnabled: Bool = true,
        isBusy: Bool = false,
        statusMessage: String = "",
        loginItemState: LoginItemState = .unavailable,
        tokenUsageEnabled: Bool = false,
        tokenUsageCard: TokenUsageMenuCard? = nil,
        providerUsage: [ProviderUsageState] = [],
        toolOrder: [UsageProvider] = MenuDisplaySettingsStore.defaultToolOrder,
        masksEmails: Bool = false,
        showsModelLimits: Bool = true,
        appIconColor: AppIconColor = .defaultColor,
        now: Date = .now
    ) {
        self.activeAccount = activeAccount
        self.inactiveAccounts = inactiveAccounts
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.refreshIntervalOptions = refreshIntervalOptions
        self.statusBarIndicatorStyle = statusBarIndicatorStyle
        self.statusBarDisplayMode = statusBarDisplayMode
        self.revealStatusItemTitleShortcut = revealStatusItemTitleShortcut
        self.sessionAccentColor = sessionAccentColor
        self.weeklyAccentColor = weeklyAccentColor
        self.usesOneUsageColor = usesOneUsageColor
        self.hasCustomUsageColors = hasCustomUsageColors
        self.usagePercentMode = usagePercentMode
        self.usageMeterLayout = usageMeterLayout
        self.pacingMarkersEnabled = pacingMarkersEnabled
        self.isBusy = isBusy
        self.statusMessage = statusMessage
        self.loginItemState = loginItemState
        self.tokenUsageEnabled = tokenUsageEnabled
        self.tokenUsageCard = tokenUsageCard
        self.providerUsage = providerUsage
        self.toolOrder = toolOrder
        self.masksEmails = masksEmails
        self.showsModelLimits = showsModelLimits
        self.appIconColor = appIconColor
        self.now = now
    }

    var allSavedAccounts: [CodexAccount] {
        [activeAccount].compactMap(\.self) + inactiveAccounts
    }

    func isAccountActiveLocally(_ account: CodexAccount) -> Bool {
        guard let activeAccount else { return false }
        return account.matchesSameAccount(as: activeAccount)
    }

    var shouldShowStatusMessage: Bool {
        !statusMessage.isEmpty && isBusy
    }

    /// The menu bar icon follows the first section. With no section at all it shows the app's own glyph.
    var statusItemSource: StatusItemSource {
        guard let first = toolSections.first else { return .nothingConnected }
        return .tool(first)
    }

    var hasStatusItemContentData: Bool {
        guard case let .tool(section) = statusItemSource else { return false }
        return !section.card.windows.isEmpty
    }

    var effectiveStatusBarDisplayMode: StatusBarDisplayMode {
        guard hasStatusItemContentData else { return .iconOnly }
        return statusBarDisplayMode
    }

    func canSelectStatusBarDisplayMode(_ mode: StatusBarDisplayMode) -> Bool {
        guard hasStatusItemContentData else { return mode == .iconOnly }
        return true
    }
}
