import Foundation
import os

/// Runs fire-and-forget main-actor work and lets a caller await all of it, including work that work starts.
final class TrackedTasks: Sendable {
    private let running = OSAllocatedUnfairLock<[UUID: Task<Void, Never>]>(initialState: [:])

    func start(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        let id = UUID()
        running.withLock { running in
            running[id] = Task { @MainActor in
                await operation()
                self.running.withLock { _ = $0.removeValue(forKey: id) }
            }
        }
    }

    func waitUntilIdle() async {
        while let task = running.withLock({ $0.values.first }) {
            await task.value
        }
    }
}
