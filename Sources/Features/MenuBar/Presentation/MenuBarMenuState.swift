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

struct ActiveAccountCard: Equatable {
    let account: CodexAccount
    let locations: [String]
    let showsUpdatedTime: Bool
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
    let pacingMarkersEnabled: Bool
    let hasCustomProgressAccentColor: Bool
    let isBusy: Bool
    let statusMessage: String
    let notificationsWhenBlockedEnabled: Bool
    let notificationsWhenOutEnabled: Bool
    let notificationAuthorizationState: NotificationAuthorizationState
    let showsPacingPrototypeMenu: Bool

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
        pacingMarkersEnabled: Bool = true,
        hasCustomProgressAccentColor: Bool = false,
        isBusy: Bool,
        statusMessage: String,
        notificationsWhenBlockedEnabled: Bool = false,
        notificationsWhenOutEnabled: Bool = false,
        notificationAuthorizationState: NotificationAuthorizationState = .unknown,
        showsPacingPrototypeMenu: Bool = false
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
        self.pacingMarkersEnabled = pacingMarkersEnabled
        self.hasCustomProgressAccentColor = hasCustomProgressAccentColor
        self.isBusy = isBusy
        self.statusMessage = statusMessage
        self.notificationsWhenBlockedEnabled = notificationsWhenBlockedEnabled
        self.notificationsWhenOutEnabled = notificationsWhenOutEnabled
        self.notificationAuthorizationState = notificationAuthorizationState
        self.showsPacingPrototypeMenu = showsPacingPrototypeMenu
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

    var activeAccountCards: [ActiveAccountCard] {
        var cards: [ActiveAccountCard] = []
        let verifiedRemoteHosts = connectedRemoteHosts.filter(\.isVerified)
        let localRemoteHosts = verifiedRemoteHosts.filter { remoteHost in
            guard let activeAccount,
                  let remoteAccount = remoteHost.activeAccount else {
                return false
            }
            return remoteAccount.matchesSameAccount(as: activeAccount)
        }
        let remoteHostsNotRepresentedByLocal = verifiedRemoteHosts.filter { remoteHost in
            guard let activeAccount,
                  let remoteAccount = remoteHost.activeAccount else {
                return true
            }
            return !remoteAccount.matchesSameAccount(as: activeAccount)
        }

        if let activeAccount {
            let locations = localRemoteHosts.isEmpty && remoteHostsNotRepresentedByLocal.isEmpty
                ? []
                : ["This Mac"] + localRemoteHosts.map(\.name)
            cards.append(
                ActiveAccountCard(
                    account: activeAccount,
                    locations: locations,
                    showsUpdatedTime: locations.isEmpty
                )
            )
        }

        for group in groupedRemoteActiveHosts(remoteHostsNotRepresentedByLocal) {
            guard let displayAccount = group.first?.activeAccount else { continue }
            cards.append(
                ActiveAccountCard(
                    account: displayAccount,
                    locations: group.map(\.name),
                    showsUpdatedTime: false
                )
            )
        }

        return cards
    }

    var activeAccountsSectionTitle: String {
        activeAccountCards.count == 1 ? "Active Account" : "Active Accounts"
    }

    func isAccountActiveLocally(_ account: CodexAccount) -> Bool {
        guard let activeAccount else { return false }
        return account.matchesSameAccount(as: activeAccount)
    }

    func activeRemoteHosts(for account: CodexAccount) -> [RemoteHostMenuState] {
        resolvedRemoteHosts.filter { remoteHost in
            guard remoteHost.connectionState == .connected,
                  remoteHost.verificationStatus == .verified,
                  remoteHost.lastVerificationError?.isEmpty ?? true,
                  let activeAccount = remoteHost.activeAccount,
                  activeAccount.matchesSameAccount(as: account) else {
                return false
            }
            return true
        }
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

    private func groupedRemoteActiveHosts(_ remoteHosts: [RemoteHostMenuState]) -> [[RemoteHostMenuState]] {
        remoteHosts.reduce(into: [[RemoteHostMenuState]]()) { groups, remoteHost in
            guard let remoteAccount = remoteHost.activeAccount else { return }
            if let index = groups.firstIndex(where: { group in
                group.contains { existingHost in
                    existingHost.activeAccount?.matchesSameAccount(as: remoteAccount) == true
                }
            }) {
                groups[index].append(remoteHost)
            } else {
                groups.append([remoteHost])
            }
        }
    }
}

private extension CodexAccount {
    func matchesSameAccount(as other: CodexAccount) -> Bool {
        id == other.id ||
            hasSameStrongAccountIdentity(as: other) ||
            hasSameDisplayAccountIdentity(as: other)
    }

    func hasSameStrongAccountIdentity(as other: CodexAccount) -> Bool {
        if let stableAccountID = normalizedIdentityValue(identity.stableAccountID),
           stableAccountID == normalizedIdentityValue(other.identity.stableAccountID) {
            return true
        }

        if let snapshotFingerprint = normalizedIdentityValue(identity.snapshotFingerprint),
           snapshotFingerprint == normalizedIdentityValue(other.identity.snapshotFingerprint) {
            return true
        }

        if let authPrincipalIdentity = identity.authPrincipalIdentity,
           authPrincipalIdentity.isMeaningful,
           authPrincipalIdentity == other.identity.authPrincipalIdentity {
            return true
        }

        if let workspaceIdentity = identity.workspaceIdentity,
           workspaceIdentity.isMeaningful,
           workspaceIdentity == other.identity.workspaceIdentity {
            return true
        }

        return false
    }

    func hasSameDisplayAccountIdentity(as other: CodexAccount) -> Bool {
        normalizedInspectableEmail != nil
            && normalizedInspectableEmail == other.normalizedInspectableEmail
            && normalizedCodexPlanType(effectivePlanType) == normalizedCodexPlanType(other.effectivePlanType)
            && normalizedAccountName == other.normalizedAccountName
    }

    var normalizedInspectableEmail: String? {
        guard let email else { return nil }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    var normalizedAccountName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func normalizedIdentityValue(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }
}
