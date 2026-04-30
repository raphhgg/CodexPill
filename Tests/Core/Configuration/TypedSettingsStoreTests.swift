import AppKit
import Testing

@testable import CodexPill

@MainActor
struct MenuPreferencesStoreTests {
    @Test
    func defaultsUseRefreshAndVisibleAccountDefaults() {
        let store = MenuPreferencesStore(userDefaults: makeDefaults())

        #expect(store.refreshIntervalMinutes == 5)
        #expect(store.visibleInactiveAccountCount == 0)
        #expect(store.refreshIntervalOptions == [1, 2, 5, 10, 15, 30])
        #expect(store.visibleInactiveAccountCountOptions == [2, 3, 5, 0])
    }

    @Test
    func preferencesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let first = MenuPreferencesStore(userDefaults: defaults)
        first.refreshIntervalMinutes = 10
        first.visibleInactiveAccountCount = 0

        let second = MenuPreferencesStore(userDefaults: defaults)

        #expect(second.refreshIntervalMinutes == 10)
        #expect(second.visibleInactiveAccountCount == 0)
    }

    @Test
    func invalidStoredValuesFallBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(99, forKey: "refreshIntervalMinutes")
        defaults.set(99, forKey: "visibleInactiveAccountCount")

        let store = MenuPreferencesStore(userDefaults: defaults)

        #expect(store.refreshIntervalMinutes == 5)
        #expect(store.visibleInactiveAccountCount == 2)
    }
}

@MainActor
struct StatusBarPreferencesStoreTests {
    @Test
    func defaultsUseCurrentStatusBarPreferences() {
        let store = StatusBarPreferencesStore(userDefaults: makeDefaults())

        #expect(store.statusBarIndicatorStyle == .twinPills)
        #expect(store.statusBarMonochrome)
        #expect(store.statusBarDisplayMode == .textOnHover)
        #expect(colorsEqual(store.progressAccentColor, StatusBarProgressColorDefaults.accent))
    }

    @Test(arguments: [
        ("notchedSquare", StatusBarIndicatorStyle.stackedBars),
        ("splitCapsule", StatusBarIndicatorStyle.twinPills)
    ])
    func legacyStyleAliasesMigrate(rawValue: String, expectedStyle: StatusBarIndicatorStyle) {
        let defaults = makeDefaults()
        defaults.set(rawValue, forKey: "statusBarIndicatorStyle")

        let store = StatusBarPreferencesStore(userDefaults: defaults)

        #expect(store.statusBarIndicatorStyle == expectedStyle)
    }

    @Test
    func customAccentPersistsAndResetRemovesCustomColor() {
        let defaults = makeDefaults()
        let accent = NSColor(calibratedRed: 0.14, green: 0.55, blue: 0.31, alpha: 1)

        let first = StatusBarPreferencesStore(userDefaults: defaults)
        first.progressAccentColor = accent

        let second = StatusBarPreferencesStore(userDefaults: defaults)
        #expect(colorsEqual(second.progressAccentColor, accent))
        #expect(second.hasCustomProgressAccentColor)

        second.resetProgressAccentColor()

        let reset = StatusBarPreferencesStore(userDefaults: defaults)
        #expect(colorsEqual(reset.progressAccentColor, StatusBarProgressColorDefaults.accent))
        #expect(!reset.hasCustomProgressAccentColor)
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

private func makeDefaults() -> UserDefaults {
    let suiteName = "TypedSettingsStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func makeAccount() -> CodexAccount {
    CodexAccount(
        id: UUID(),
        name: "Business 2",
        snapshotFileName: "business-2.json",
        createdAt: .distantPast,
        updatedAt: .distantPast,
        email: "business-2@example.com",
        planType: "team",
        rateLimits: nil,
        identity: .empty
    )
}

private func colorsEqual(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
    let left = (lhs.usingColorSpace(.deviceRGB) ?? lhs.usingColorSpace(.sRGB)) ?? lhs
    let right = (rhs.usingColorSpace(.deviceRGB) ?? rhs.usingColorSpace(.sRGB)) ?? rhs

    return abs(left.redComponent - right.redComponent) < 0.001
        && abs(left.greenComponent - right.greenComponent) < 0.001
        && abs(left.blueComponent - right.blueComponent) < 0.001
        && abs(left.alphaComponent - right.alphaComponent) < 0.001
}
