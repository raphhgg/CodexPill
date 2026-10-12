import Foundation
import os

@testable import Refill

/// A Codex status source that counts every read, of the account in use or a saved one, and has nothing to return.
final class CountingAccountStatusClient: CodexAccountStatusClient, SavedCodexAccountStatusClient {
    private let reads = OSAllocatedUnfairLock(initialState: 0)

    var readCount: Int { reads.withLock { $0 } }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        reads.withLock { $0 += 1 }
        throw DisabledAccountStatusClientError.unexpectedRead
    }

    func readSavedAccountStatus(authData _: Data) async -> SavedCodexAccountStatusRead {
        reads.withLock { $0 += 1 }
        return SavedCodexAccountStatusRead(status: .failure(DisabledAccountStatusClientError.unexpectedRead), rotatedAuthData: nil)
    }
}
