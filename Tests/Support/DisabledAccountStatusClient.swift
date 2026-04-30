import Foundation

@testable import CodexPill

struct DisabledAccountStatusClient: CodexAccountStatusClient, SavedCodexAccountStatusClient {
    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        throw DisabledAccountStatusClientError.unexpectedRead
    }

    func readSavedAccountStatus(authData: Data) async throws -> CodexAccountStatus {
        throw DisabledAccountStatusClientError.unexpectedRead
    }
}

enum DisabledAccountStatusClientError: Error {
    case unexpectedRead
}
