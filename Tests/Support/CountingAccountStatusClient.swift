import Foundation
import os

@testable import RUsage

/// A Codex status source that counts every read and has nothing to return.
final class CountingAccountStatusClient: CodexAccountStatusClient {
    private let reads = OSAllocatedUnfairLock(initialState: 0)

    var readCount: Int { reads.withLock { $0 } }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        reads.withLock { $0 += 1 }
        throw DisabledAccountStatusClientError.unexpectedRead
    }
}
