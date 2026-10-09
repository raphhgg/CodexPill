import AppKit

struct MenuBarMenuState {
    let activeAccount: CodexAccount?
    let inactiveAccounts: [CodexAccount]
    let visibleInactiveAccountCount: Int
    let visibleInactiveAccountCountOptions: [Int]
    let refreshIntervalMinutes: Int
    let refreshIntervalOptions: [Int]
    let statusBarMonochrome: Bool
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
    let tokenUsagePeriod: CodexTokenUsagePeriod
    let tokenUsageChartStyle: TokenUsageChartStyle
    let tokenUsageLoadingAnimationStyle: TokenUsageLoadingAnimationStyle
    let tokenUsagePeakScope: TokenUsagePeakScope
    let tokenUsageCard: TokenUsageMenuCard?

    init(
        activeAccount: CodexAccount?,
        inactiveAccounts: [CodexAccount],
        visibleInactiveAccountCount: Int,
        visibleInactiveAccountCountOptions: [Int],
        refreshIntervalMinutes: Int,
        refreshIntervalOptions: [Int],
        statusBarMonochrome: Bool,
        statusBarIndicatorStyle: StatusBarIndicatorStyle,
        statusBarDisplayMode: StatusBarDisplayMode,
        revealStatusItemTitleShortcut: KeyboardShortcut? = .defaultRevealStatusItemTitle,
        sessionAccentColor: NSColor = StatusBarProgressColorDefaults.accent,
        weeklyAccentColor: NSColor = StatusBarProgressColorDefaults.accent,
        usesOneUsageColor: Bool = true,
        hasCustomUsageColors: Bool = false,
        usagePercentMode: UsagePercentMode = .used,
        usageMeterLayout: UsageMeterLayout = .classic,
        pacingMarkersEnabled: Bool = true,
        isBusy: Bool,
        statusMessage: String,
        loginItemState: LoginItemState = .unavailable,
        tokenUsageEnabled: Bool = false,
        tokenUsagePeriod: CodexTokenUsagePeriod = .last30Days,
        tokenUsageChartStyle: TokenUsageChartStyle = .dailyBars,
        tokenUsageLoadingAnimationStyle: TokenUsageLoadingAnimationStyle = .waves,
        tokenUsagePeakScope: TokenUsagePeakScope = .currentPeriod,
        tokenUsageCard: TokenUsageMenuCard? = nil
    ) {
        self.activeAccount = activeAccount
        self.inactiveAccounts = inactiveAccounts
        self.visibleInactiveAccountCount = visibleInactiveAccountCount
        self.visibleInactiveAccountCountOptions = visibleInactiveAccountCountOptions
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.refreshIntervalOptions = refreshIntervalOptions
        self.statusBarMonochrome = statusBarMonochrome
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
        self.tokenUsagePeriod = tokenUsagePeriod
        self.tokenUsageChartStyle = tokenUsageChartStyle
        self.tokenUsageLoadingAnimationStyle = tokenUsageLoadingAnimationStyle
        self.tokenUsagePeakScope = tokenUsagePeakScope
        self.tokenUsageCard = tokenUsageCard
    }

    var canAddAccount: Bool {
        !isBusy
    }

    var canShowAbout: Bool {
        !isBusy
    }

    var canRemoveSavedAccounts: Bool {
        !isBusy && allSavedAccounts.count > 0
    }

    var canRenameSavedAccounts: Bool {
        !isBusy && allSavedAccounts.count > 0
    }

    var allSavedAccounts: [CodexAccount] {
        accountCatalogProjection.allSavedAccounts
    }

    var activeAccountCards: [ActiveAccountCard] {
        activeAccountsProjection.activeAccountCards
    }

    var activeAccountsSectionTitle: String {
        activeAccountsProjection.sectionTitle
    }

    func isAccountActiveLocally(_ account: CodexAccount) -> Bool {
        guard let activeAccount else { return false }
        return account.matchesSameAccount(as: activeAccount)
    }

    var accountCatalogEntries: [MenuBarAccountCatalogEntry] {
        accountCatalogProjection.accountCatalogEntries
    }

    var visibleAccountEntries: [MenuBarAccountCatalogEntry] {
        let activeEntries = accountCatalogEntries.filter(\.isActive)
        let nonActiveEntries = accountCatalogEntries.filter { !$0.isActive }
        guard shouldLimitVisibleInactiveAccounts else {
            return activeEntries + nonActiveEntries
        }
        return activeEntries + Array(nonActiveEntries.prefix(nonActiveAccountVisibilityLimit))
    }

    var overflowAccountEntries: [MenuBarAccountCatalogEntry] {
        guard shouldLimitVisibleInactiveAccounts else { return [] }
        let activeCount = accountCatalogEntries.filter(\.isActive).count
        let visibleCount = activeCount + nonActiveAccountVisibilityLimit
        guard accountCatalogEntries.count > visibleCount else { return [] }
        return Array(accountCatalogEntries.dropFirst(visibleCount))
    }

    var accountListSectionTitle: String {
        shouldShowOtherAccountsList ? "Other Accounts" : "Accounts"
    }

    var visibleDisplayAccountEntries: [MenuBarAccountCatalogEntry] {
        guard shouldShowOtherAccountsList else {
            return shouldShowSingleAccountManagementMenu ? [] : visibleAccountEntries
        }
        return visibleEntries(from: accountEntriesExcludingActiveLocalAccount)
    }

    var overflowDisplayAccountEntries: [MenuBarAccountCatalogEntry] {
        guard shouldShowOtherAccountsList else {
            return shouldShowSingleAccountManagementMenu ? [] : overflowAccountEntries
        }
        return overflowEntries(from: accountEntriesExcludingActiveLocalAccount)
    }

    var shouldShowSingleAccountManagementMenu: Bool {
        allSavedAccounts.count == 1
    }

    var shouldShowActiveAccountManagementMenu: Bool {
        allSavedAccounts.count > 1 && activeAccount != nil
    }

    var accountForAccountManagementMenu: CodexAccount? {
        activeAccount ?? allSavedAccounts.first
    }

    private var nonActiveAccountVisibilityLimit: Int {
        max(0, visibleInactiveAccountCount)
    }

    private var shouldLimitVisibleInactiveAccounts: Bool {
        visibleInactiveAccountCount > 0
    }

    private var shouldShowOtherAccountsList: Bool {
        allSavedAccounts.count > 1
    }

    private var accountEntriesExcludingActiveLocalAccount: [MenuBarAccountCatalogEntry] {
        guard let activeAccount else { return accountCatalogEntries }
        return accountCatalogEntries.filter { !$0.account.matchesSameAccount(as: activeAccount) }
    }

    private func visibleEntries(from entries: [MenuBarAccountCatalogEntry]) -> [MenuBarAccountCatalogEntry] {
        guard shouldLimitVisibleInactiveAccounts else { return entries }
        return Array(entries.prefix(nonActiveAccountVisibilityLimit))
    }

    private func overflowEntries(from entries: [MenuBarAccountCatalogEntry]) -> [MenuBarAccountCatalogEntry] {
        guard shouldLimitVisibleInactiveAccounts else { return [] }
        guard entries.count > nonActiveAccountVisibilityLimit else { return [] }
        return Array(entries.dropFirst(nonActiveAccountVisibilityLimit))
    }

    var shouldShowStatusMessage: Bool {
        guard !statusMessage.isEmpty else { return false }
        return isBusy
    }

    var hasStatusItemContentData: Bool {
        guard let activeAccount else { return false }
        return activeAccount.usage?.window(.session) != nil || activeAccount.usage?.window(.weekly) != nil
    }

    var effectiveStatusBarDisplayMode: StatusBarDisplayMode {
        guard hasStatusItemContentData else { return .iconOnly }
        return statusBarDisplayMode
    }

    func canSelectStatusBarDisplayMode(_ mode: StatusBarDisplayMode) -> Bool {
        guard hasStatusItemContentData else { return mode == .iconOnly }
        return true
    }

    private var accountCatalogProjection: MenuBarAccountCatalogProjection {
        MenuBarAccountCatalogProjection(
            activeAccount: activeAccount,
            inactiveAccounts: inactiveAccounts
        )
    }

    private var activeAccountsProjection: ActiveAccountsProjection {
        ActiveAccountsProjection(activeAccount: activeAccount)
    }
}
