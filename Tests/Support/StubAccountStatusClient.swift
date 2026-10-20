import Foundation

@testable import rusage

struct StubAccountStatusClient: CodexAccountStatusClient {
    private let result: Result<CodexAccountStatus, Error>

    init(status: CodexAccountStatus) {
        result = .success(status)
    }

    init(error: Error) {
        result = .failure(error)
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        try result.get()
    }
}
