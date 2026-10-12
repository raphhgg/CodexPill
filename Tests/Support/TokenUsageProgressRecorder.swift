import Foundation

@testable import Refill

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

    /// File counts only, for tests that don't look at the days read so far.
    var fileCounts: [TokenUsageScanProgress] {
        updates.map { TokenUsageScanProgress(scannedFiles: $0.scannedFiles, totalFiles: $0.totalFiles) }
    }

    var isEmpty: Bool {
        updates.isEmpty
    }
}
