import Foundation
import Testing

@testable import CodexPill

@MainActor
struct MenuDisplaySettingsStoreTests {
    @Test
    func preferencesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let first = MenuDisplaySettingsStore(userDefaults: defaults)
        first.refreshIntervalMinutes = 10
        first.visibleInactiveAccountCount = 0

        let second = MenuDisplaySettingsStore(userDefaults: defaults)

        #expect(second.refreshIntervalMinutes == 10)
        #expect(second.visibleInactiveAccountCount == 0)
    }

    @Test
    func invalidStoredValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(99, forKey: "refreshIntervalMinutes")
        defaults.set(99, forKey: "visibleInactiveAccountCount")

        let store = MenuDisplaySettingsStore(userDefaults: defaults)

        #expect(store.refreshIntervalMinutes == 5)
        #expect(store.visibleInactiveAccountCount == 5)
    }
}

@MainActor
struct StatusItemSettingsStoreTests {
    @Test(arguments: [
        ("notchedSquare", StatusBarIndicatorStyle.stackedBars),
        ("splitCapsule", StatusBarIndicatorStyle.twinPills)
    ])
    func legacyStyleAliasesMigrate(rawValue: String, expectedStyle: StatusBarIndicatorStyle) {
        let defaults = makeDefaults()
        defaults.set(rawValue, forKey: "statusBarIndicatorStyle")

        let store = StatusItemSettingsStore(userDefaults: defaults)

        #expect(store.statusBarIndicatorStyle == expectedStyle)
    }

    @Test
    func customAccentPersistsAndResetRemovesCustomColor() {
        let defaults = makeDefaults()
        let accent = StatusItemAccentColor(red: 0.14, green: 0.55, blue: 0.31, alpha: 1)

        let first = StatusItemSettingsStore(userDefaults: defaults)
        first.sessionAccentColor = accent
        first.pacingMarkersEnabled = false

        let second = StatusItemSettingsStore(userDefaults: defaults)
        #expect(second.sessionAccentColor == accent)
        #expect(second.hasCustomUsageColors)
        #expect(!second.pacingMarkersEnabled)

        second.resetUsageColors()

        let reset = StatusItemSettingsStore(userDefaults: defaults)
        #expect(reset.sessionAccentColor == nil)
        #expect(!reset.hasCustomUsageColors)
    }

    @Test
    func existingAccentColorBecomesSessionAndWeeklyColor() throws {
        let defaults = makeDefaults()
        let accent = StatusItemAccentColor(red: 0.14, green: 0.55, blue: 0.31, alpha: 1)
        defaults.set(try JSONEncoder().encode(accent), forKey: "progressAccentColor")

        let store = StatusItemSettingsStore(userDefaults: defaults)

        #expect(store.sessionAccentColor == accent)
        #expect(store.effectiveWeeklyAccentColor == accent)
        #expect(store.usesOneUsageColor)
        #expect(store.usagePercentMode == .used)
        #expect(store.usageMeterLayout == .classic)
    }

    @Test
    func separateWeeklyColorPersistsAndSameColorOptionOverridesIt() {
        let defaults = makeDefaults()
        let session = StatusItemAccentColor(red: 0.14, green: 0.55, blue: 0.31, alpha: 1)
        let weekly = StatusItemAccentColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1)

        let first = StatusItemSettingsStore(userDefaults: defaults)
        first.sessionAccentColor = session
        first.weeklyAccentColor = weekly
        first.usesOneUsageColor = false
        first.usagePercentMode = .left
        first.usageMeterLayout = .compact

        let second = StatusItemSettingsStore(userDefaults: defaults)
        #expect(second.effectiveWeeklyAccentColor == weekly)
        #expect(second.usagePercentMode == .left)
        #expect(second.usageMeterLayout == .compact)

        second.usesOneUsageColor = true
        #expect(StatusItemSettingsStore(userDefaults: defaults).effectiveWeeklyAccentColor == session)

        second.resetUsageColors()
        let reset = StatusItemSettingsStore(userDefaults: defaults)
        #expect(reset.weeklyAccentColor == nil)
        #expect(reset.usesOneUsageColor)
        #expect(!reset.hasCustomUsageColors)
    }

    @Test
    func revealShortcutPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let shortcut = KeyboardShortcut(keyCode: 11, modifiers: [.control, .shift])

        let first = StatusItemSettingsStore(userDefaults: defaults)
        first.revealStatusItemTitleShortcut = shortcut

        let second = StatusItemSettingsStore(userDefaults: defaults)

        #expect(second.revealStatusItemTitleShortcut == shortcut)
    }

    @Test
    func revealShortcutCanBeCleared() {
        let defaults = makeDefaults()
        let first = StatusItemSettingsStore(userDefaults: defaults)
        first.revealStatusItemTitleShortcut = nil

        let second = StatusItemSettingsStore(userDefaults: defaults)

        #expect(second.revealStatusItemTitleShortcut == nil)
    }
}

@MainActor
struct RemoteHostSettingsStoreTests {
    @Test
    func remoteHostStatesPersistAndPreserveSorting() {
        let defaults = makeDefaults()
        let first = RemoteHostSettingsStore(userDefaults: defaults)
        first.upsertRemoteHost(RemoteHost(destination: "user@debian-vm", displayName: "Debian VM"))
        first.upsertRemoteHost(RemoteHost(destination: "user@buildbox", displayName: "Build Box"))

        let second = RemoteHostSettingsStore(userDefaults: defaults)

        #expect(second.remoteHostStates.map(\.host.displayName) == ["Build Box", "Debian VM"])
    }

    @Test
    func updateAndRemoveHelpersUseDestinationIdentity() {
        let store = RemoteHostSettingsStore(userDefaults: makeDefaults())
        let buildbox = RemoteHost(destination: "user@buildbox", displayName: "Build Box")
        let debian = RemoteHost(destination: "user@debian-vm", displayName: "Debian VM")
        let accountID = UUID()

        store.upsertRemoteHost(buildbox)
        store.updateRemoteHostState(for: debian) { state in
            state.installedAccountIDs = [accountID]
        }
        store.removeRemoteHost(destination: buildbox.destination)

        #expect(store.remoteHostStates.count == 1)
        #expect(store.remoteHostState(for: debian.destination)?.installedAccountIDs == [accountID])
    }

    @Test
    func legacyRemoteHostKeysMigrateAsDesiredButUnverified() throws {
        let defaults = makeDefaults()
        let host = RemoteHost(destination: "user@buildbox", displayName: "Build Box")
        let account = makeAccount()
        defaults.set(try JSONEncoder().encode(host), forKey: "remoteHost")
        defaults.set(try JSONEncoder().encode([account.id]), forKey: "remoteHostInstalledAccountIDs")
        defaults.set(try JSONEncoder().encode(account), forKey: "remoteHostActiveAccount")

        let store = RemoteHostSettingsStore(userDefaults: defaults)

        #expect(store.remoteHostStates == [
            PersistedRemoteHostState(
                host: host,
                installedAccountIDs: [account.id],
                desiredAccountID: account.id,
                verifiedAccount: nil,
                verificationStatus: .unverified
            )
        ])
        #expect(defaults.object(forKey: "remoteHost") == nil)
        #expect(defaults.object(forKey: "remoteHostInstalledAccountIDs") == nil)
        #expect(defaults.object(forKey: "remoteHostActiveAccount") == nil)
    }

    @Test
    func canonicalRemoteHostsIgnoreAndClearLegacyRemoteHostKeys() throws {
        let defaults = makeDefaults()
        let legacyHost = RemoteHost(destination: "user@debian-vm", displayName: "Debian VM")
        let legacyAccount = makeAccount()
        defaults.set(try JSONEncoder().encode([PersistedRemoteHostState]()), forKey: "remoteHosts")
        defaults.set(try JSONEncoder().encode(legacyHost), forKey: "remoteHost")
        defaults.set(try JSONEncoder().encode([legacyAccount.id]), forKey: "remoteHostInstalledAccountIDs")
        defaults.set(try JSONEncoder().encode(legacyAccount), forKey: "remoteHostActiveAccount")

        let store = RemoteHostSettingsStore(userDefaults: defaults)

        #expect(store.remoteHostStates.isEmpty)
        #expect(defaults.object(forKey: "remoteHost") == nil)
        #expect(defaults.object(forKey: "remoteHostInstalledAccountIDs") == nil)
        #expect(defaults.object(forKey: "remoteHostActiveAccount") == nil)
    }

    @Test
    func fullVerificationStatePersistsAcrossInstances() throws {
        let defaults = makeDefaults()
        let account = makeAccount(name: "Business 2")
        let detectedID = UUID()
        let first = RemoteHostSettingsStore(userDefaults: defaults)
        first.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "Build Box"),
                installedAccountIDs: [account.id],
                desiredAccountID: account.id,
                verifiedAccount: account,
                verificationStatus: .verified
            ),
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@debian-vm", displayName: "Debian VM"),
                desiredAccountID: account.id,
                detectedAccountID: detectedID,
                verificationStatus: .failed,
                lastVerificationError: "Debian VM is using Business 1, not Business 2."
            )
        ]

        let second = RemoteHostSettingsStore(userDefaults: defaults)

        let buildbox = try #require(second.remoteHostState(for: "user@buildbox"))
        #expect(buildbox.installedAccountIDs == [account.id])
        #expect(buildbox.verifiedAccount == account)
        #expect(buildbox.verificationStatus == .verified)
        let debian = try #require(second.remoteHostState(for: "user@debian-vm"))
        #expect(debian.desiredAccountID == account.id)
        #expect(debian.detectedAccountID == detectedID)
        #expect(debian.verificationStatus == .failed)
        #expect(debian.lastVerificationError == "Debian VM is using Business 1, not Business 2.")
    }

    @Test
    func upsertingExistingHostKeepsItsAccountState() throws {
        let store = RemoteHostSettingsStore(userDefaults: makeDefaults())
        let account = makeAccount(name: "Business 2")
        store.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "Build Box"),
                installedAccountIDs: [account.id],
                desiredAccountID: account.id,
                verifiedAccount: account,
                verificationStatus: .verified
            )
        ]

        store.upsertRemoteHost(RemoteHost(destination: "user@buildbox", displayName: "Primary Build Box"))

        let persisted = try #require(store.remoteHostState(for: "user@buildbox"))
        #expect(persisted.host.displayName == "Primary Build Box")
        #expect(persisted.installedAccountIDs == [account.id])
        #expect(persisted.desiredAccountID == account.id)
        #expect(persisted.verifiedAccount == account)
        #expect(persisted.verificationStatus == .verified)
    }

    @Test
    func singleHostActiveAccountMarksHostVerified() {
        let defaults = makeDefaults()
        let account = makeAccount(name: "Business 2")
        let first = RemoteHostSettingsStore(userDefaults: defaults)
        first.configuredRemoteHost = RemoteHost(destination: "user@buildbox", displayName: "Build Box")
        first.remoteHostActiveAccount = account

        let second = RemoteHostSettingsStore(userDefaults: defaults)

        #expect(second.remoteHostActiveAccount == account)
        #expect(second.remoteHostDesiredAccountID == account.id)
        #expect(second.remoteHostState(for: "user@buildbox")?.verificationStatus == .verified)
    }

    @Test
    func singleHostDesiredAccountLeavesHostUnverified() {
        let defaults = makeDefaults()
        let accountID = UUID()
        let first = RemoteHostSettingsStore(userDefaults: defaults)
        first.configuredRemoteHost = RemoteHost(destination: "user@buildbox", displayName: "Build Box")
        first.remoteHostDesiredAccountID = accountID

        let second = RemoteHostSettingsStore(userDefaults: defaults)

        #expect(second.remoteHostDesiredAccountID == accountID)
        #expect(second.remoteHostActiveAccount == nil)
        #expect(second.remoteHostState(for: "user@buildbox")?.verificationStatus == .unverified)
    }

    @Test
    func legacyRemoteHostsPayloadMigratesAsDesiredButUnverified() throws {
        struct LegacyRemoteHostState: Codable {
            let installedAccountIDs: [UUID]
            let host: RemoteHost
            let activeAccount: CodexAccount
        }

        let defaults = makeDefaults()
        let host = RemoteHost(destination: "user@buildbox", displayName: "Build Box")
        let account = makeAccount(name: "Business 2")
        defaults.set(
            try JSONEncoder().encode([
                LegacyRemoteHostState(installedAccountIDs: [account.id], host: host, activeAccount: account)
            ]),
            forKey: "remoteHosts"
        )

        let store = RemoteHostSettingsStore(userDefaults: defaults)

        #expect(store.remoteHostStates == [
            PersistedRemoteHostState(
                host: host,
                installedAccountIDs: [account.id],
                desiredAccountID: account.id,
                verifiedAccount: nil,
                verificationStatus: .unverified
            )
        ])
    }
}

@MainActor
struct NotificationPreferencesStoreTests {
    @Test
    func notificationTogglesPersist() {
        let defaults = makeDefaults()
        let first = NotificationPreferencesStore(userDefaults: defaults)
        first.notificationsWhenBlockedEnabled = true
        first.notificationsWhenOutEnabled = true

        let second = NotificationPreferencesStore(userDefaults: defaults)

        #expect(second.notificationsWhenBlockedEnabled)
        #expect(second.notificationsWhenOutEnabled)
    }

    @Test
    func legacyBeforeYouRunOutKeyMigratesToOutToggle() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "notificationsBeforeYouRunOutEnabled")

        let store = NotificationPreferencesStore(userDefaults: defaults)

        #expect(store.notificationsWhenOutEnabled)
    }
}

@MainActor
struct NotificationStateStoreTests {
    @Test
    func perAccountNotificationStatePersists() throws {
        let defaults = makeDefaults()
        let accountID = UUID()
        let now = Date()

        let first = NotificationStateStore(userDefaults: defaults)
        first.updateAccountNotificationState(for: accountID) { state in
            state.isArmed = false
            state.lastNotification = PersistedAccountNotificationRecord(
                reason: .whenOut,
                window: PersistedAccountNotificationWindow(sessionResetAt: now, weeklyResetAt: nil),
                notifiedAt: now
            )
        }

        let second = NotificationStateStore(userDefaults: defaults)
        let persisted = try #require(second.accountNotificationState(for: accountID))

        #expect(!persisted.isArmed)
        #expect(persisted.lastNotification?.reason == .whenOut)
        #expect(persisted.lastNotification?.notifiedAt == now)
    }

    @Test
    func updateHelperInsertsAndUpdatesDeterministically() throws {
        let store = NotificationStateStore(userDefaults: makeDefaults())
        let laterID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

        store.updateAccountNotificationState(for: laterID) { state in
            state.isArmed = false
        }
        store.updateAccountNotificationState(for: earlierID) { state in
            state.isArmed = true
        }
        store.updateAccountNotificationState(for: laterID) { state in
            state.isArmed = true
        }

        #expect(store.accountNotificationStates.map(\.accountID) == [earlierID, laterID])
        #expect(try #require(store.accountNotificationState(for: laterID)).isArmed)
    }
}

@MainActor
struct TokenUsagePreferencesStoreTests {
    @Test
    func preferencesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let first = TokenUsagePreferencesStore(userDefaults: defaults)
        first.isEnabled = true
        first.chartStyle = .sparkline
        first.loadingAnimationStyle = .random
        first.peakScope = .allTime

        let second = TokenUsagePreferencesStore(userDefaults: defaults)

        #expect(second.isEnabled)
        #expect(second.chartStyle == .sparkline)
        #expect(second.loadingAnimationStyle == .random)
        #expect(second.peakScope == .allTime)
    }

    @Test
    func hiddenPeriodsMigrateToThirtyDays() {
        let defaults = makeDefaults()
        defaults.set(CodexTokenUsagePeriod.last7Days.rawValue, forKey: "tokenUsagePeriod")

        let store = TokenUsagePreferencesStore(userDefaults: defaults)

        #expect(store.period == .last30Days)
        #expect(defaults.object(forKey: "tokenUsagePeriod") as? Int == CodexTokenUsagePeriod.last30Days.rawValue)
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "TypedSettingsStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
