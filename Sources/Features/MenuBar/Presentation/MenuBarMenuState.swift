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
    let isBusy: Bool
    let statusMessage: String

    var canSaveCurrentAccount: Bool {
        !isBusy && activeAccount == nil
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
}
