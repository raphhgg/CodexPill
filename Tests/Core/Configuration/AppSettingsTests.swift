import AppKit
import Testing

@testable import CodexPill

@MainActor
struct AppSettingsTests {
    @Test
    func progressAccentColorDefaultAndReset() {
        let defaults = makeDefaults()
        let settings = AppSettings(userDefaults: defaults)

        #expect(colorsEqual(settings.progressAccentColor, StatusBarProgressColorDefaults.accent))
        #expect(settings.hasCustomProgressAccentColor == false)

        settings.progressAccentColor = NSColor(calibratedRed: 0.12, green: 0.45, blue: 0.78, alpha: 1)
        #expect(settings.hasCustomProgressAccentColor)

        settings.resetProgressAccentColor()

        #expect(colorsEqual(settings.progressAccentColor, StatusBarProgressColorDefaults.accent))
        #expect(settings.hasCustomProgressAccentColor == false)
    }

    @Test
    func progressAccentColorPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let accent = NSColor(calibratedRed: 0.14, green: 0.55, blue: 0.31, alpha: 1)

        let first = AppSettings(userDefaults: defaults)
        first.progressAccentColor = accent

        let second = AppSettings(userDefaults: defaults)

        #expect(colorsEqual(second.progressAccentColor, accent))
        #expect(second.hasCustomProgressAccentColor)
    }

    @Test
    func configuredRemoteHostPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let first = AppSettings(userDefaults: defaults)
        first.configuredRemoteHost = RemoteHost(destination: "user@buildbox", displayName: "Build Box")
        first.remoteHostInstalledAccountIDs = [UUID()]

        let second = AppSettings(userDefaults: defaults)

        #expect(second.configuredRemoteHost == RemoteHost(destination: "user@buildbox", displayName: "Build Box"))
        #expect(second.remoteHostInstalledAccountIDs.count == 1)
    }

    @Test
    func remoteHostStatesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let account = CodexAccount(
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
        let first = AppSettings(userDefaults: defaults)
        first.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "Build Box"),
                installedAccountIDs: [account.id],
                desiredAccountID: account.id,
                verifiedAccount: account,
                verificationStatus: .verified
            ),
            PersistedRemoteHostState(host: RemoteHost(destination: "user@debian-vm", displayName: "Debian VM"))
        ]

        let second = AppSettings(userDefaults: defaults)

        #expect(second.remoteHostStates.count == 2)
        #expect(second.remoteHostStates[0].host.displayName == "Build Box")
        #expect(second.remoteHostStates[0].desiredAccountID == account.id)
        #expect(second.remoteHostStates[0].verifiedAccount == account)
        #expect(second.remoteHostStates[0].verificationStatus == .verified)
        #expect(second.remoteHostStates[1].host.displayName == "Debian VM")
    }

    @Test
    func blankRemoteHostDisplayNameFallsBackToHostname() {
        let host = RemoteHost(destination: "user@buildbox", displayName: "   ")

        #expect(host.displayName == "buildbox")
    }

    @Test
    func remoteHostVerifiedAccountPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let account = CodexAccount(
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

        let first = AppSettings(userDefaults: defaults)
        first.configuredRemoteHost = RemoteHost(destination: "user@buildbox", displayName: "Build Box")
        first.remoteHostActiveAccount = account

        let second = AppSettings(userDefaults: defaults)

        #expect(second.remoteHostActiveAccount == account)
        #expect(second.remoteHostState(for: "user@buildbox")?.verificationStatus == .verified)
    }

    @Test
    func remoteHostDesiredAccountPersistsWithoutMarkingHostVerified() {
        let defaults = makeDefaults()
        let accountID = UUID()

        let first = AppSettings(userDefaults: defaults)
        first.configuredRemoteHost = RemoteHost(destination: "user@buildbox", displayName: "Build Box")
        first.remoteHostDesiredAccountID = accountID

        let second = AppSettings(userDefaults: defaults)

        #expect(second.remoteHostDesiredAccountID == accountID)
        #expect(second.remoteHostActiveAccount == nil)
        #expect(second.remoteHostState(for: "user@buildbox")?.verificationStatus == .unverified)
    }

    @Test
    func detectedRemoteAccountPersistsAcrossInstances() throws {
        let defaults = makeDefaults()
        let desiredID = UUID()
        let detectedID = UUID()

        let first = AppSettings(userDefaults: defaults)
        first.remoteHostStates = [
            PersistedRemoteHostState(
                host: RemoteHost(destination: "user@buildbox", displayName: "Build Box"),
                desiredAccountID: desiredID,
                verifiedAccount: nil,
                detectedAccountID: detectedID,
                verificationStatus: .failed,
                lastVerificationError: "Build Box is using Business 1, not Business 2."
            )
        ]

        let second = AppSettings(userDefaults: defaults)
        let persisted = try #require(second.remoteHostState(for: "user@buildbox"))
        #expect(persisted.desiredAccountID == desiredID)
        #expect(persisted.detectedAccountID == detectedID)
        #expect(persisted.verificationStatus == .failed)
    }

    @Test
    func updateAndRemoveRemoteHostStateUseDestinationIdentity() {
        let defaults = makeDefaults()
        let settings = AppSettings(userDefaults: defaults)
        let buildbox = RemoteHost(destination: "user@buildbox", displayName: "Build Box")
        let debian = RemoteHost(destination: "user@debian-vm", displayName: "Debian VM")
        let accountID = UUID()

        settings.upsertRemoteHost(buildbox)
        settings.upsertRemoteHost(debian)
        settings.updateRemoteHostState(for: debian) { state in
            state.installedAccountIDs = [accountID]
        }

        #expect(settings.remoteHostStates.count == 2)
        #expect(settings.remoteHostState(for: buildbox.destination)?.installedAccountIDs.isEmpty == true)
        #expect(settings.remoteHostState(for: debian.destination)?.installedAccountIDs == [accountID])

        settings.removeRemoteHost(destination: buildbox.destination)

        #expect(settings.remoteHostStates.count == 1)
        #expect(settings.remoteHostStates.first?.host == debian)
    }

    @Test
    func upsertingExistingHostPreservesInstalledAccountsAndActiveAccount() throws {
        let defaults = makeDefaults()
        let settings = AppSettings(userDefaults: defaults)
        let originalHost = RemoteHost(destination: "user@buildbox", displayName: "Build Box")
        let renamedHost = RemoteHost(destination: "user@buildbox", displayName: "Primary Build Box")
        let account = CodexAccount(
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

        settings.remoteHostStates = [
            PersistedRemoteHostState(
                host: originalHost,
                installedAccountIDs: [account.id],
                desiredAccountID: account.id,
                verifiedAccount: account,
                verificationStatus: .verified
            )
        ]

        settings.upsertRemoteHost(renamedHost)

        let persisted = try #require(settings.remoteHostState(for: renamedHost.destination))
        #expect(persisted.host.displayName == "Primary Build Box")
        #expect(persisted.installedAccountIDs == [account.id])
        #expect(persisted.desiredAccountID == account.id)
        #expect(persisted.verifiedAccount == account)
        #expect(persisted.verificationStatus == .verified)
    }

    @Test
    func remoteHostStatesMigrateFromLegacyKeysAsDesiredButUnverified() throws {
        let defaults = makeDefaults()
        let host = RemoteHost(destination: "user@buildbox", displayName: "Build Box")
        let account = CodexAccount(
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
        defaults.set(try JSONEncoder().encode(host), forKey: "remoteHost")
        defaults.set(try JSONEncoder().encode([account.id]), forKey: "remoteHostInstalledAccountIDs")
        defaults.set(try JSONEncoder().encode(account), forKey: "remoteHostActiveAccount")

        let settings = AppSettings(userDefaults: defaults)

        #expect(settings.remoteHostStates == [
            PersistedRemoteHostState(
                host: host,
                installedAccountIDs: [account.id],
                desiredAccountID: account.id,
                verifiedAccount: nil,
                verificationStatus: .unverified,
                lastVerificationError: nil
            )
        ])
    }

    @Test
    func remoteHostStatesMigrateFromLegacyRemoteHostsPayloadAsDesiredButUnverified() throws {
        struct LegacyRemoteHostState: Codable {
            let installedAccountIDs: [UUID]
            let host: RemoteHost
            let activeAccount: CodexAccount
        }

        let defaults = makeDefaults()
        let host = RemoteHost(destination: "user@buildbox", displayName: "Build Box")
        let account = CodexAccount(
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
        defaults.set(
            try JSONEncoder().encode([
                LegacyRemoteHostState(
                    installedAccountIDs: [account.id],
                    host: host,
                    activeAccount: account
                )
            ]),
            forKey: "remoteHosts"
        )

        let settings = AppSettings(userDefaults: defaults)

        #expect(settings.remoteHostStates == [
            PersistedRemoteHostState(
                host: host,
                installedAccountIDs: [account.id],
                desiredAccountID: account.id,
                verifiedAccount: nil,
                verificationStatus: .unverified,
                lastVerificationError: nil
            )
        ])
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func colorsEqual(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let left = (lhs.usingColorSpace(.deviceRGB) ?? lhs.usingColorSpace(.sRGB)) ?? lhs
        let right = (rhs.usingColorSpace(.deviceRGB) ?? rhs.usingColorSpace(.sRGB)) ?? rhs

        return abs(left.redComponent - right.redComponent) < 0.001
            && abs(left.greenComponent - right.greenComponent) < 0.001
            && abs(left.blueComponent - right.blueComponent) < 0.001
            && abs(left.alphaComponent - right.alphaComponent) < 0.001
    }
}
