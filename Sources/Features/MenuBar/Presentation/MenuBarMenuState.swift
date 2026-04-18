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
    let progressAccentColor: NSColor
    let hasCustomProgressAccentColor: Bool
    let isBusy: Bool
    let statusMessage: String

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
        progressAccentColor: NSColor = StatusBarProgressColorDefaults.accent,
        hasCustomProgressAccentColor: Bool = false,
        isBusy: Bool,
        statusMessage: String
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
        self.progressAccentColor = progressAccentColor
        self.hasCustomProgressAccentColor = hasCustomProgressAccentColor
        self.isBusy = isBusy
        self.statusMessage = statusMessage
    }

    var canSaveCurrentAccount: Bool {
        !isBusy
    }

    var canSignInAnotherAccount: Bool {
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
        [activeAccount].compactMap { $0 } + inactiveAccounts
    }

    var visibleInactiveAccounts: [CodexAccount] {
        guard visibleInactiveAccountCount > 0 else { return inactiveAccounts }
        return Array(inactiveAccounts.prefix(visibleInactiveAccountCount))
    }

    var overflowInactiveAccounts: [CodexAccount] {
        guard visibleInactiveAccountCount > 0, inactiveAccounts.count > visibleInactiveAccountCount else { return [] }
        return Array(inactiveAccounts.dropFirst(visibleInactiveAccountCount))
    }

    var shouldShowStatusMessage: Bool {
        guard !statusMessage.isEmpty else { return false }
        return isBusy
    }

    var hasStatusItemContentData: Bool {
        guard let activeAccount else { return false }
        return activeAccount.rateLimits?.primary != nil || activeAccount.rateLimits?.secondary != nil
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
