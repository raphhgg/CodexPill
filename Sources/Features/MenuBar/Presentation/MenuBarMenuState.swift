import AppKit

enum NotificationAuthorizationState: Equatable {
    case notDetermined
    case authorized
    case denied
    case unknown
}

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
    let desiredAccount: CodexAccount?
    let activeAccount: CodexAccount?
    let detectedAccount: CodexAccount?
    let verificationStatus: PersistedRemoteHostState.VerificationStatus
    let lastVerificationError: String?
    let deployedAccountIDs: [UUID]

    init(
        name: String,
        destination: String = "",
        connectionState: RemoteHostConnectionState,
        desiredAccount: CodexAccount? = nil,
        activeAccount: CodexAccount?,
        detectedAccount: CodexAccount? = nil,
        verificationStatus: PersistedRemoteHostState.VerificationStatus = .verified,
        lastVerificationError: String? = nil,
        deployedAccountIDs: [UUID] = []
    ) {
        self.name = name
        self.destination = destination
        self.connectionState = connectionState
        self.desiredAccount = desiredAccount
        self.activeAccount = activeAccount
        self.detectedAccount = detectedAccount
        self.verificationStatus = verificationStatus
        self.lastVerificationError = lastVerificationError
        self.deployedAccountIDs = deployedAccountIDs
    }

    func hasDeployedAccount(_ account: CodexAccount) -> Bool {
        deployedAccountIDs.contains(account.id)
    }

    var shouldShowRemoteAccountCard: Bool {
        connectionState != .disconnected && displayAccount != nil
    }

    var displayAccount: CodexAccount? {
        activeAccount ?? detectedAccount ?? desiredAccount
    }

    var isVerified: Bool {
        activeAccount != nil && verificationStatus == .verified
    }
}

struct MenuBarMenuState {
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
    let notificationsWhenBlockedEnabled: Bool
    let notificationsWhenOutEnabled: Bool
    let notificationAuthorizationState: NotificationAuthorizationState

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
        statusMessage: String,
        notificationsWhenBlockedEnabled: Bool = false,
        notificationsWhenOutEnabled: Bool = false,
        notificationAuthorizationState: NotificationAuthorizationState = .unknown
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
        self.notificationsWhenBlockedEnabled = notificationsWhenBlockedEnabled
        self.notificationsWhenOutEnabled = notificationsWhenOutEnabled
        self.notificationAuthorizationState = notificationAuthorizationState
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

    var canConfigureHosts: Bool {
        !isBusy
    }

    var allSavedAccounts: [CodexAccount] {
        accountCatalogProjection.allSavedAccounts
    }

    var resolvedRemoteHosts: [RemoteHostMenuState] {
        accountCatalogProjection.resolvedRemoteHosts
    }

    var connectedRemoteHosts: [RemoteHostMenuState] {
        accountCatalogProjection.connectedRemoteHosts
    }

    var remoteTargetAvailabilities: [String: AccountTargetAvailability] {
        accountCatalogProjection.remoteTargetAvailabilities
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

    private var nonActiveAccountVisibilityLimit: Int {
        max(0, visibleInactiveAccountCount)
    }

    private var shouldLimitVisibleInactiveAccounts: Bool {
        visibleInactiveAccountCount > 0
    }

    var shouldShowStatusMessage: Bool {
        guard !statusMessage.isEmpty else { return false }
        return isBusy
    }

    var hasStatusItemContentData: Bool {
        guard let activeAccount else { return false }
        return activeAccount.rateLimits?.primary != nil || activeAccount.rateLimits?.secondary != nil
    }

    var availabilitySnapshots: [AccountAvailabilitySnapshot] {
        accountCatalogProjection.availabilitySnapshots
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
            inactiveAccounts: inactiveAccounts,
            remoteHosts: remoteHosts
        )
    }
}
