import Foundation

@testable import rusage

final class CodexAppProcessProbe: CodexAppProcessClient, @unchecked Sendable {
    var relaunchResult = CodexRelaunch.relaunched
    private(set) var relaunchCount = 0
    /// When set, relaunching waits at this gate, which keeps a switch in flight.
    var relaunchGate: TestGate?

    func relaunchCodex() async throws -> CodexRelaunch {
        await relaunchGate?.pass()
        relaunchCount += 1
        return relaunchResult
    }
}
