import Foundation

@testable import rusage

struct DisabledAccountStatusClient: CodexAccountStatusClient, SavedCodexAccountStatusClient {
    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        throw DisabledAccountStatusClientError.unexpectedRead
    }

    func readSavedAccountStatus(authData: Data) async -> SavedCodexAccountStatusRead {
        SavedCodexAccountStatusRead(status: .failure(DisabledAccountStatusClientError.unexpectedRead), rotatedAuthData: nil)
    }
}

enum DisabledAccountStatusClientError: Error {
    case unexpectedRead
}
