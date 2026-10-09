import Foundation
import os

@testable import CodexPill

/// Returns the reading a test sets and counts how often the runtime asked for it.
final class UsageProviderSourceProbe: UsageProviderSource {
    let provider: UsageProvider
    let staleAfter: TimeInterval
    private let state: OSAllocatedUnfairLock<(reading: UsageProviderReading, readCount: Int)>

    init(provider: UsageProvider, staleAfter: TimeInterval = 3_600, reading: UsageProviderReading) {
        self.provider = provider
        self.staleAfter = staleAfter
        state = OSAllocatedUnfairLock(initialState: (reading, 0))
    }

    var reading: UsageProviderReading {
        get { state.withLock { $0.reading } }
        set { state.withLock { $0.reading = newValue } }
    }

    var readCount: Int {
        state.withLock { $0.readCount }
    }

    func readUsage(now _: Date) async -> UsageProviderReading {
        state.withLock { state in
            state.readCount += 1
            return state.reading
        }
    }
}
