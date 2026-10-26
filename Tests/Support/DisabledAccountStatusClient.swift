import Foundation

@testable import RUsage

struct DisabledAccountStatusClient: CodexAccountStatusClient {
    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        throw DisabledAccountStatusClientError.unexpectedRead
    }
}

enum DisabledAccountStatusClientError: Error {
    case unexpectedRead
}
