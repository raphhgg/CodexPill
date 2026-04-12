import Foundation
import Testing

@testable import CodexPill

struct CodexAppServerClientTests {
    @Test
    func appServerSessionStateRequiresRateLimitsBeforeStatusIsComplete() {
        let state = AppServerSessionState()

        state.setAccountResponse(
            AppServerAccountResponse(
                account: .init(
                    email: "user@example.com",
                    planType: "plus"
                )
            )
        )

        #expect(state.partialStatus()?.email == "user@example.com")
        #expect(state.completeStatus() == nil)

        state.setRateLimitResponse(
            AppServerRateLimitsResponse(
                rateLimits: RateLimitSnapshot(
                    limitId: "codex",
                    limitName: nil,
                    planType: "plus",
                    primary: RateLimitWindow(
                        usedPercent: 42,
                        resetsAt: 1_776_005_472,
                        windowDurationMins: 300
                    ),
                    secondary: RateLimitWindow(
                        usedPercent: 18,
                        resetsAt: 1_776_512_418,
                        windowDurationMins: 10_080
                    )
                )
            )
        )

        #expect(state.completeStatus()?.rateLimits?.primary?.usedPercent == 42)
        #expect(state.completeStatus()?.rateLimits?.secondary?.usedPercent == 18)
    }

    @Test
    func appServerFailurePrefersStderrOverTerminationCode() {
        let error = appServerFailure(
            stderr: "warning on stderr",
            terminationStatus: 128,
            timedOut: false
        )

        #expect(error == .server("warning on stderr"))
    }

    @Test
    func appServerFailureUsesTerminationCodeWhenNoStderrExists() {
        let error = appServerFailure(
            stderr: nil,
            terminationStatus: 128,
            timedOut: false
        )

        #expect(error == .terminated(128))
    }

    @Test
    func appServerFailureUsesStderrForTimeoutWhenPresent() {
        let error = appServerFailure(
            stderr: "network warning",
            terminationStatus: nil,
            timedOut: true
        )

        #expect(error == .server("network warning"))
    }

    @Test
    func appServerFailureFallsBackToTimeoutWithoutStderrOrExitCode() {
        let error = appServerFailure(
            stderr: nil,
            terminationStatus: nil,
            timedOut: true
        )

        #expect(error == .timeout)
    }

    @Test
    func readCurrentAccountStatusRetriesOnceWhenFirstResponseMissesRateLimits() async throws {
        let accountOnly = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            rateLimits: nil
        )
        let fullStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            rateLimits: makeRateLimitsSnapshot()
        )
        let reader = StatusReaderStub(results: [
            .success(accountOnly),
            .success(fullStatus)
        ])
        let sleeper = SleepRecorder()
        let client = CodexAppServerClient(
            statusReader: reader.read,
            sleeper: sleeper.sleep
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false, true])
        #expect(await sleeper.recordedDurations() == [.seconds(1)])
        #expect(status.email == "user@example.com")
        #expect(status.rateLimits == fullStatus.rateLimits)
    }

    @Test
    func readCurrentAccountStatusRetriesAfterTransientFirstFailure() async throws {
        let fullStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            rateLimits: makeRateLimitsSnapshot()
        )
        let reader = StatusReaderStub(results: [
            .failure(StatusReadError.transientFailure),
            .success(fullStatus)
        ])
        let sleeper = SleepRecorder()
        let client = CodexAppServerClient(
            statusReader: reader.read,
            sleeper: sleeper.sleep
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false, true])
        #expect(await sleeper.recordedDurations() == [.seconds(1)])
        #expect(status.rateLimits == fullStatus.rateLimits)
    }

    @Test
    func readCurrentAccountStatusReturnsPartialStatusWhenRetryStillHasNoRateLimits() async throws {
        let firstStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            rateLimits: nil
        )
        let secondStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "team",
            rateLimits: nil
        )
        let reader = StatusReaderStub(results: [
            .success(firstStatus),
            .success(secondStatus)
        ])
        let client = CodexAppServerClient(
            statusReader: reader.read,
            sleeper: { _ in }
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false, true])
        #expect(status.email == "user@example.com")
        #expect(status.planType == "team")
        #expect(status.rateLimits == nil)
    }

    @Test
    func readCurrentAccountStatusReturnsFirstPartialStatusWhenRetryFails() async throws {
        let firstStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            rateLimits: nil
        )
        let reader = StatusReaderStub(results: [
            .success(firstStatus),
            .failure(StatusReadError.transientFailure)
        ])
        let client = CodexAppServerClient(
            statusReader: reader.read,
            sleeper: { _ in }
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false, true])
        #expect(status.email == "user@example.com")
        #expect(status.planType == "plus")
        #expect(status.rateLimits == nil)
    }

    private func makeRateLimitsSnapshot() -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            limitID: "codex",
            limitName: nil,
            planType: "plus",
            primary: CodexRateLimitWindow(
                usedPercent: 12,
                resetsAt: Date(timeIntervalSince1970: 1_776_005_472),
                windowDurationMinutes: 300
            ),
            secondary: CodexRateLimitWindow(
                usedPercent: 32,
                resetsAt: Date(timeIntervalSince1970: 1_776_512_418),
                windowDurationMinutes: 10_080
            ),
            fetchedAt: Date(timeIntervalSince1970: 1_776_000_000)
        )
    }
}

private actor StatusReaderStub {
    private var remainingResults: [Result<CodexAccountStatus, Error>]
    private var refreshTokens: [Bool] = []

    init(results: [Result<CodexAccountStatus, Error>]) {
        remainingResults = results
    }

    func read(refreshToken: Bool) async throws -> CodexAccountStatus {
        refreshTokens.append(refreshToken)
        guard !remainingResults.isEmpty else {
            throw StatusReadError.noStubbedResult
        }

        let result = remainingResults.removeFirst()
        switch result {
        case .success(let status):
            return status
        case .failure(let error):
            throw error
        }
    }

    func recordedRefreshTokens() -> [Bool] {
        refreshTokens
    }
}

private actor SleepRecorder {
    private var durations: [Duration] = []

    func sleep(_ duration: Duration) async {
        durations.append(duration)
    }

    func recordedDurations() -> [Duration] {
        durations
    }
}

private enum StatusReadError: Error {
    case transientFailure
    case noStubbedResult
}
