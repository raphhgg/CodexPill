import Foundation

@testable import CodexPill

final class TokenUsageProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TokenUsageScanProgress] = []

    func append(_ progress: TokenUsageScanProgress) {
        lock.lock()
        storage.append(progress)
        lock.unlock()
    }

    var updates: [TokenUsageScanProgress] {
        lock.lock()
        let updates = storage
        lock.unlock()
        return updates
    }

    var isEmpty: Bool {
        updates.isEmpty
    }
}
