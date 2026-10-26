import Foundation
import os

@testable import RUsage

/// A tool connection whose reading the test sets. It counts reads. Once disconnected it reads nothing. Its own sign-in
/// and sign-out fail with `notice` when one is set.
final class ProviderConnectionProbe: ProviderConnection {
    struct State {
        var reading: UsageProviderReading
        var readCount = 0
        var isDisconnected = false
        var isShown = true
        var ownSignIn = ProviderOwnSignIn.unsupported
        var notice: ProviderNotice?
    }

    let provider: UsageProvider
    let staleAfter: TimeInterval
    let refreshInterval: TimeInterval
    private let state: OSAllocatedUnfairLock<State>

    init(
        provider: UsageProvider,
        staleAfter: TimeInterval = 3_600,
        refreshInterval: TimeInterval = ProviderUsageRuntime.refreshInterval,
        reading: UsageProviderReading
    ) {
        self.provider = provider
        self.staleAfter = staleAfter
        self.refreshInterval = refreshInterval
        state = OSAllocatedUnfairLock(initialState: State(reading: reading))
    }

    var isShown: Bool {
        state.withLock { $0.isShown }
    }

    func setShown(_ isShown: Bool) {
        state.withLock { $0.isShown = isShown }
    }

    func update(_ change: @Sendable (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    var reading: UsageProviderReading {
        get { state.withLock { $0.reading } }
        set { state.withLock { $0.reading = newValue } }
    }

    var readCount: Int { state.withLock { $0.readCount } }

    func readUsage(now _: Date) async -> UsageProviderReading {
        state.withLock { state in
            guard !state.isDisconnected else { return .notConnected }
            state.readCount += 1
            return state.reading
        }
    }

    var isConnected: Bool { state.withLock { !$0.isDisconnected && $0.reading != .notConnected } }

    func connect() async { update { $0.isDisconnected = false } }
    func disconnect() async { update { $0.isDisconnected = true } }

    var ownSignIn: ProviderOwnSignIn { state.withLock { $0.ownSignIn } }

    func signIn() async throws(ProviderNotice) {
        if let notice = state.withLock({ $0.notice }) { throw notice }
    }

    func signOut() async throws(ProviderNotice) {
        if let notice = state.withLock({ $0.notice }) { throw notice }
    }
}
