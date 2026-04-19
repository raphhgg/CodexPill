import AppKit

enum RemoteHostConnectionState: String, Codable, Equatable {
    case connected
    case disconnected
    case syncing

    var menuTitle: String {
        switch self {
        case .connected:
            return "Connected"
        case .disconnected:
            return "Disconnected"
        case .syncing:
            return "Syncing"
        }
    }
}

struct RemoteHostMenuState: Codable, Equatable {
    let name: String
    let destination: String
    let connectionState: RemoteHostConnectionState
    let activeAccount: CodexAccount?
    let deployedAccountIDs: [UUID]

    init(
        name: String,
        destination: String = "",
        connectionState: RemoteHostConnectionState,
        activeAccount: CodexAccount?,
        deployedAccountIDs: [UUID] = []
    ) {
        self.name = name
        self.destination = destination
        self.connectionState = connectionState
        self.activeAccount = activeAccount
        self.deployedAccountIDs = deployedAccountIDs
    }

    func hasDeployedAccount(_ account: CodexAccount) -> Bool {
        deployedAccountIDs.contains(account.id)
    }

    var shouldShowRemoteAccountCard: Bool {
        activeAccount != nil && connectionState != .disconnected
    }
}

struct MenuBarAccountCatalogEntry: Equatable {
    let account: CodexAccount
    let placement: MenuBarAccountPlacement?

    var isActive: Bool {
        placement != nil
    }
}

struct MenuBarMenuState {
    private static let nonActiveAccountVisibilityLimit = 3

    let activeAccount: CodexAccount?
    let inactiveAccounts: [CodexAccount]
    let remoteHosts: [RemoteHostMenuState]
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
        remoteHosts: [RemoteHostMenuState] = [],
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
        self.remoteHosts = remoteHosts
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

    var canConfigureHosts: Bool {
        !isBusy
    }

    var allSavedAccounts: [CodexAccount] {
        [activeAccount].compactMap { $0 } + inactiveAccounts
    }

    var connectedRemoteHosts: [RemoteHostMenuState] {
        remoteHosts.filter(\.shouldShowRemoteAccountCard)
    }

    var accountCatalogEntries: [MenuBarAccountCatalogEntry] {
        let remoteActiveIDs = Set(connectedRemoteHosts.compactMap(\.activeAccount?.id))

        let activeEntries = allSavedAccounts.compactMap { account -> MenuBarAccountCatalogEntry? in
            let isLocal = activeAccount?.id == account.id
            let isRemote = remoteActiveIDs.contains(account.id)
            guard isLocal || isRemote else { return nil }
            return MenuBarAccountCatalogEntry(
                account: account,
                placement: placement(isLocal: isLocal, isRemote: isRemote)
            )
        }
        .sorted(by: compareActiveEntries)

        let activeIDs = Set(activeEntries.map(\.account.id))
        let nonActiveEntries = allSavedAccounts
            .filter { !activeIDs.contains($0.id) }
            .map { MenuBarAccountCatalogEntry(account: $0, placement: nil) }
            .sorted(by: compareCatalogEntries)

        return activeEntries + nonActiveEntries
    }

    var visibleAccountEntries: [MenuBarAccountCatalogEntry] {
        let activeEntries = accountCatalogEntries.filter(\.isActive)
        let nonActiveEntries = accountCatalogEntries.filter { !$0.isActive }
        return activeEntries + Array(nonActiveEntries.prefix(Self.nonActiveAccountVisibilityLimit))
    }

    var overflowAccountEntries: [MenuBarAccountCatalogEntry] {
        let activeCount = accountCatalogEntries.filter(\.isActive).count
        let visibleCount = activeCount + Self.nonActiveAccountVisibilityLimit
        guard accountCatalogEntries.count > visibleCount else { return [] }
        return Array(accountCatalogEntries.dropFirst(visibleCount))
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

    private func placement(isLocal: Bool, isRemote: Bool) -> MenuBarAccountPlacement? {
        switch (isLocal, isRemote) {
        case (true, true):
            return .localAndRemote
        case (true, false):
            return .local
        case (false, true):
            return .remote
        case (false, false):
            return nil
        }
    }

    private func compareActiveEntries(_ lhs: MenuBarAccountCatalogEntry, _ rhs: MenuBarAccountCatalogEntry) -> Bool {
        let leftRank = placementRank(lhs.placement)
        let rightRank = placementRank(rhs.placement)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        return lhs.account.name.localizedCaseInsensitiveCompare(rhs.account.name) == .orderedAscending
    }

    private func placementRank(_ placement: MenuBarAccountPlacement?) -> Int {
        switch placement {
        case .localAndRemote:
            return 0
        case .local:
            return 1
        case .remote:
            return 2
        case .none:
            return 3
        }
    }

    private func compareCatalogEntries(_ lhs: MenuBarAccountCatalogEntry, _ rhs: MenuBarAccountCatalogEntry) -> Bool {
        let leftKey = rankingKey(for: lhs.account)
        let rightKey = rankingKey(for: rhs.account)
        if leftKey.bucket != rightKey.bucket {
            return leftKey.bucket < rightKey.bucket
        }
        if leftKey.availableAt != rightKey.availableAt {
            return leftKey.availableAt < rightKey.availableAt
        }
        if leftKey.weeklyUsedPercent != rightKey.weeklyUsedPercent {
            return leftKey.weeklyUsedPercent < rightKey.weeklyUsedPercent
        }
        if leftKey.sessionUsedPercent != rightKey.sessionUsedPercent {
            return leftKey.sessionUsedPercent < rightKey.sessionUsedPercent
        }
        return lhs.account.name.localizedCaseInsensitiveCompare(rhs.account.name) == .orderedAscending
    }

    private func rankingKey(for account: CodexAccount, now: Date = .now) -> AccountRankingKey {
        let session = account.rateLimits?.primary
        let weekly = account.rateLimits?.secondary
        let sessionUsedPercent = session?.displayedUsedPercent(at: now) ?? 100
        let weeklyUsedPercent = weekly?.displayedUsedPercent(at: now) ?? 100
        let sessionReset = session?.resetsAt ?? .distantFuture
        let weeklyReset = weekly?.resetsAt ?? .distantFuture

        if weeklyUsedPercent < 100, sessionUsedPercent < 100 {
            return AccountRankingKey(
                bucket: 0,
                availableAt: min(sessionReset, weeklyReset),
                weeklyUsedPercent: weeklyUsedPercent,
                sessionUsedPercent: sessionUsedPercent
            )
        }

        if weeklyUsedPercent < 100, sessionUsedPercent >= 100 {
            return AccountRankingKey(
                bucket: 1,
                availableAt: sessionReset,
                weeklyUsedPercent: weeklyUsedPercent,
                sessionUsedPercent: sessionUsedPercent
            )
        }

        if weeklyUsedPercent >= 100 {
            let weeklyCutoff = now.addingTimeInterval(24 * 60 * 60)
            let bucket = weeklyReset > weeklyCutoff ? 3 : 2
            return AccountRankingKey(
                bucket: bucket,
                availableAt: weeklyReset,
                weeklyUsedPercent: weeklyUsedPercent,
                sessionUsedPercent: sessionUsedPercent
            )
        }

        return AccountRankingKey(
            bucket: 4,
            availableAt: .distantFuture,
            weeklyUsedPercent: weeklyUsedPercent,
            sessionUsedPercent: sessionUsedPercent
        )
    }
}

private struct AccountRankingKey {
    let bucket: Int
    let availableAt: Date
    let weeklyUsedPercent: Int
    let sessionUsedPercent: Int
}
