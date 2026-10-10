import Foundation
import os

@testable import CodexPill

/// A tool connection whose reading and saved accounts the test sets. It counts reads and records switches.
final class ProviderConnectionProbe: ProviderConnection {
    struct State {
        var reading: UsageProviderReading
        var readCount = 0
        var accounts: [ProviderAccount] = []
        var switchedTo: [UUID] = []
        var switchError: ProviderNotice?
        /// Reads started while this is set wait at it, returning the reading they started with.
        var readGate: TestGate?
        var readingAfterSwitch: UsageProviderReading?
    }

    let provider: UsageProvider
    let staleAfter: TimeInterval
    let signIn: (any ProviderSignIn)?
    private let state: OSAllocatedUnfairLock<State>

    init(
        provider: UsageProvider,
        staleAfter: TimeInterval = 3_600,
        reading: UsageProviderReading,
        signIn: (any ProviderSignIn)? = nil
    ) {
        self.provider = provider
        self.staleAfter = staleAfter
        self.signIn = signIn
        state = OSAllocatedUnfairLock(initialState: State(reading: reading))
    }

    func update(_ change: @Sendable (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    var reading: UsageProviderReading {
        get { state.withLock { $0.reading } }
        set { state.withLock { $0.reading = newValue } }
    }

    var readCount: Int { state.withLock { $0.readCount } }
    var switchedTo: [UUID] { state.withLock { $0.switchedTo } }

    func readUsage(now _: Date) async -> UsageProviderReading {
        let (reading, gate) = state.withLock { state in
            state.readCount += 1
            return (state.reading, state.readGate)
        }
        await gate?.pass()
        return reading
    }

    func connect() async {}
    func disconnect() async {}

    func savedAccounts() async throws(ProviderNotice) -> [ProviderAccount] {
        state.withLock { $0.accounts }
    }

    func switchAccount(to id: UUID) async throws(ProviderNotice) {
        let error = state.withLock { state -> ProviderNotice? in
            if let error = state.switchError { return error }
            state.switchedTo.append(id)
            state.accounts = state.accounts.map { ProviderAccount(id: $0.id, email: $0.email, isActive: $0.id == id) }
            if let next = state.readingAfterSwitch { state.reading = next }
            return nil
        }
        if let error { throw error }
    }

    func addCurrentAccount() async throws(ProviderNotice) {}
    func removeAccount(_: UUID) async throws(ProviderNotice) {}
}
