import Foundation

@testable import Refill

/// A `CursorUsage` over an isolated defaults suite, a settable token lookup, and a settable usage-summary response.
final class CursorUsageFixture: CursorAccessTokenSource, CursorUsageWebClient, @unchecked Sendable {
    let settings: CursorUsageSettingsStore
    let defaults: UserDefaults
    private(set) var usage: CursorUsage!
    private let suiteName = "CursorUsageFixture-\(UUID().uuidString)"
    private let lock = NSLock()
    private var currentLookup: CursorAccessTokenLookup = .cursorNotInstalled
    private var currentResponse: Result<Data, CursorUsageWebError> = .failure(.transport)
    private var requests = 0
    private var currentDatabaseError: CursorStateDatabaseError?

    /// Synthetic usage summary: 82.29% of the plan used while dollars show 2000 of 2000 (bonus credit),
    /// with $12.34 of a $50.00 on-demand cap spent.
    static let proPlanWithCappedOnDemand = #"""
    {"billingCycleStart":"2026-09-30T15:23:08.000Z","billingCycleEnd":"2026-10-30T15:23:08.000Z","membershipType":"pro","isUnlimited":false,
     "individualUsage":{"plan":{"enabled":true,"used":2000,"limit":2000,"totalPercentUsed":82.29},"onDemand":{"enabled":true,"used":1234,"limit":5000}}}
    """#

    init(now: @escaping @Sendable () -> Date = Date.init, refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval) {
        defaults = UserDefaults(suiteName: suiteName)!
        settings = CursorUsageSettingsStore(userDefaults: defaults)
        usage = CursorUsage(
            settings: settings,
            client: CursorUsageClient(tokenSource: self, webClient: self, now: now),
            refreshInterval: refreshInterval
        )
    }

    var tokenLookup: CursorAccessTokenLookup {
        get { lock.withLock { currentLookup } }
        set { lock.withLock { currentLookup = newValue } }
    }

    var response: Result<Data, CursorUsageWebError> {
        get { lock.withLock { currentResponse } }
        set { lock.withLock { currentResponse = newValue } }
    }

    var requestCount: Int {
        lock.withLock { requests }
    }

    func signIn(expiresAt: Date, summary: String) {
        tokenLookup = .token(CursorAccessTokenFixtures.token(expiresAt: expiresAt))
        response = .success(Data(summary.utf8))
    }

    /// The error reading Cursor's database throws, or nil to read `tokenLookup`.
    var databaseError: CursorStateDatabaseError? {
        get { lock.withLock { currentDatabaseError } }
        set { lock.withLock { currentDatabaseError = newValue } }
    }

    func lookup() throws -> CursorAccessTokenLookup {
        if let databaseError { throw databaseError }
        return tokenLookup
    }

    func usageSummary(using _: CursorAccessToken) async throws -> Data {
        let response = lock.withLock {
            requests += 1
            return currentResponse
        }
        return try response.get()
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
