import Foundation

@testable import CodexPill

final class CodexAppProcessProbe: CodexAppProcessClient, @unchecked Sendable {
    var availabilityError: Error?
    private(set) var availabilityCheckCount = 0
    private(set) var relaunchCount = 0

    func assertCodexAvailable() throws {
        availabilityCheckCount += 1
        if let availabilityError {
            throw availabilityError
        }
    }

    func relaunchCodex() async throws {
        relaunchCount += 1
    }
}
