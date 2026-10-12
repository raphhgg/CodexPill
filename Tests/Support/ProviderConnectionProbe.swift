import Foundation
import os

@testable import CodexPill

/// A tool connection whose reading the test sets. It counts reads.
final class ProviderConnectionProbe: ProviderConnection {
    struct State {
        var reading: UsageProviderReading
        var readCount = 0
        /// Reads started while this is set wait at it, returning the reading they started with.
        var readGate: TestGate?
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

}
