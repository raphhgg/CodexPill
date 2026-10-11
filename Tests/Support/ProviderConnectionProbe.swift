import Foundation
import os

@testable import CodexPill

/// A tool connection whose reading and saved accounts the test sets. It counts reads, records switches and inactive
/// reads in `events`, and lets a gate hold a sign-in or an inactive read.
final class ProviderConnectionProbe: ProviderConnection {
    struct State {
        var reading: UsageProviderReading
        var readCount = 0
        var accounts: [ProviderAccount] = []
        var switchedTo: [UUID] = []
        var switchError: ProviderNotice?
        /// A switch waits here before it changes anything.
        var switchGate: TestGate?
        /// Reads started while this is set wait at it, returning the reading they started with.
        var readGate: TestGate?
        var readingAfterSwitch: UsageProviderReading?
        /// A sign-in waits here until the gate opens or its task is cancelled.
        var signInGate: TestGate?
        var signInError: ProviderNotice?
        var accountAddedBySignIn: ProviderAccount?
        /// Inactive reads wait here, after recording that they started.
        var inactiveReadGate: TestGate?
        var usageAfterInactiveRead: UsageSnapshot?
        var events: [String] = []
    }

    let provider: UsageProvider
    let staleAfter: TimeInterval
    let signInAvailability: ProviderSignInAvailability
    private let state: OSAllocatedUnfairLock<State>

    init(
        provider: UsageProvider,
        staleAfter: TimeInterval = 3_600,
        reading: UsageProviderReading,
        signInAvailability: ProviderSignInAvailability = .unsupported
    ) {
        self.provider = provider
        self.staleAfter = staleAfter
        self.signInAvailability = signInAvailability
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
    var events: [String] { state.withLock { $0.events } }

    func readUsage(now _: Date) async -> UsageProviderReading {
        let (reading, gate) = state.withLock { state in
            state.readCount += 1
            return (state.reading, state.readGate)
        }
        await gate?.pass()
        return reading
    }

    var isConnected: Bool { reading != .notConnected }

    func connect() async {}
    func disconnect() async {}

    func savedAccounts() async throws(ProviderNotice) -> [ProviderAccount] {
        state.withLock { $0.accounts }
    }

    func switchAccount(to id: UUID) async throws(ProviderNotice) {
        await state.withLock { $0.switchGate }?.pass()
        let error = state.withLock { state -> ProviderNotice? in
            if let error = state.switchError { return error }
            state.switchedTo.append(id)
            state.events.append("switch \(id.uuidString.prefix(4))")
            state.accounts = state.accounts.map { ProviderAccount(id: $0.id, email: $0.email, isActive: $0.id == id) }
            if let next = state.readingAfterSwitch { state.reading = next }
            return nil
        }
        if let error { throw error }
    }

    func addAccount() async throws(ProviderNotice) -> Bool {
        let gate = state.withLock { $0.signInGate }
        if let gate {
            await withTaskCancellationHandler {
                await gate.pass()
            } onCancel: {
                Task { await gate.open() }
            }
        }
        guard !Task.isCancelled else { return false }
        let error = state.withLock { state -> ProviderNotice? in
            if let error = state.signInError { return error }
            if let added = state.accountAddedBySignIn { state.accounts.append(added) }
            return nil
        }
        if let error { throw error }
        return true
    }

    func addCurrentAccount() async throws(ProviderNotice) {}
    func removeAccount(_: UUID) async throws(ProviderNotice) {}

    func refreshInactiveAccount(_ id: UUID, now _: Date) async {
        let gate = state.withLock { state in
            state.events.append("read \(id.uuidString.prefix(4))")
            return state.inactiveReadGate
        }
        await gate?.pass()
        state.withLock { state in
            state.events.append("saved \(id.uuidString.prefix(4))")
            guard let usage = state.usageAfterInactiveRead, let index = state.accounts.firstIndex(where: { $0.id == id }) else { return }
            state.accounts[index].usage = usage
        }
    }
}
