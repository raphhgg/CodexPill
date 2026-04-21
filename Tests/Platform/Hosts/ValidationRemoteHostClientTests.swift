import Foundation
import Testing

@testable import CodexPill

struct ValidationRemoteHostClientTests {
    @Test
    func switchFlowInstallsThenReturnsRemoteStatusForActiveAccount() async throws {
        let account = makeAccount(
            name: "Business 2",
            email: "business-2@example.com",
            usedPercent: 81
        )
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = ValidationRemoteHostClient(
            seedStates: [PersistedRemoteHostState(host: host)]
        )

        let initialState = try await client.installationState(for: account, on: host)
        #expect(initialState == .missing)

        try await client.installAccount(account, on: host)
        let installedState = try await client.installationState(for: account, on: host)
        #expect(installedState == .installed)

        try await client.switchToAccount(account, on: host)
        let status = try await client.readCurrentAccountStatus(on: host)

        #expect(status.email == "business-2@example.com")
        #expect(status.planType == "team")
        #expect(status.rateLimits?.primary?.usedPercent == 81)
    }

    @Test
    func seededHostStateStartsInstalledAndReadable() async throws {
        let account = makeAccount(
            name: "Business 3",
            email: "business-3@example.com",
            usedPercent: 44
        )
        let host = RemoteHost(destination: "user@debian-vm", displayName: "debian-vm")
        let client = ValidationRemoteHostClient(
            seedStates: [
                PersistedRemoteHostState(
                    host: host,
                    installedAccountIDs: [account.id],
                    activeAccount: account
                )
            ]
        )

        #expect(try await client.installationState(for: account, on: host) == .installed)

        let status = try await client.readCurrentAccountStatus(on: host)
        #expect(status.email == "business-3@example.com")
        #expect(status.rateLimits?.primary?.usedPercent == 44)
    }

    @Test
    func readingHostWithoutActiveAccountFailsClearly() async {
        let host = RemoteHost(destination: "user@buildbox", displayName: "buildbox")
        let client = ValidationRemoteHostClient(seedStates: [PersistedRemoteHostState(host: host)])

        await #expect(throws: RemoteHostClientError.commandFailed("Validation host buildbox has no active account.")) {
            try await client.readCurrentAccountStatus(on: host)
        }
    }

    private func makeAccount(name: String, email: String, usedPercent: Int) -> CodexAccount {
        CodexAccount(
            id: UUID(),
            name: name,
            snapshotFileName: "\(UUID().uuidString).json",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            email: email,
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: nil,
                limitName: nil,
                planType: "team",
                primary: CodexRateLimitWindow(
                    usedPercent: usedPercent,
                    resetsAt: Date(timeIntervalSince1970: 2_000_000_000),
                    windowDurationMinutes: 300
                ),
                secondary: CodexRateLimitWindow(
                    usedPercent: 16,
                    resetsAt: Date(timeIntervalSince1970: 2_000_500_000),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: .distantPast
            ),
            identity: .empty
        )
    }
}
