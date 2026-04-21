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
                    planType: "plus",
                    stableAccountID: nil,
                    authPrincipalIdentity: nil,
                    workspaceIdentity: nil,
                    snapshotFingerprint: nil
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
    func readCurrentAccountStatusRetriesWhenFirstResponseHasOnlyWeeklyRateLimits() async throws {
        let weeklyOnly = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "plus",
                primary: nil,
                secondary: CodexRateLimitWindow(
                    usedPercent: 16,
                    resetsAt: Date(timeIntervalSince1970: 1_776_512_418),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: Date(timeIntervalSince1970: 1_776_000_000)
            )
        )
        let fullStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            rateLimits: makeRateLimitsSnapshot()
        )
        let reader = StatusReaderStub(results: [
            .success(weeklyOnly),
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
        #expect(status.rateLimits?.primary?.usedPercent == 12)
        #expect(status.rateLimits?.secondary?.usedPercent == 32)
    }

    @Test
    func readCurrentAccountStatusMergesPartialRateLimitWindowsAcrossRetries() async throws {
        let weeklyOnly = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "plus",
                primary: nil,
                secondary: CodexRateLimitWindow(
                    usedPercent: 18,
                    resetsAt: Date(timeIntervalSince1970: 1_776_512_418),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: Date(timeIntervalSince1970: 1_776_000_000)
            )
        )
        let sessionOnly = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "codex",
                limitName: nil,
                planType: "plus",
                primary: CodexRateLimitWindow(
                    usedPercent: 69,
                    resetsAt: Date(timeIntervalSince1970: 1_776_005_472),
                    windowDurationMinutes: 300
                ),
                secondary: nil,
                fetchedAt: Date(timeIntervalSince1970: 1_776_000_100)
            )
        )
        let reader = StatusReaderStub(results: [
            .success(weeklyOnly),
            .success(sessionOnly)
        ])
        let client = CodexAppServerClient(
            statusReader: reader.read,
            sleeper: { _ in }
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false, true])
        #expect(status.rateLimits?.primary?.usedPercent == 69)
        #expect(status.rateLimits?.secondary?.usedPercent == 18)
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

    @Test
    func makeAppServerCommandPrefersExplicitOverride() {
        let command = CodexAppServerClient.makeAppServerCommand(
            environment: ["CODEX_CLI_PATH": "/tmp/custom-codex"]
        )

        #expect(command.executableURL.path == "/tmp/custom-codex")
        #expect(command.arguments == ["app-server"])
    }

    @Test
    func makeAppServerCommandFallsBackToEnvWhenNoKnownExecutableExists() {
        let command = CodexAppServerClient.makeAppServerCommand(environment: [:])

        #expect(command.arguments == ["codex", "app-server"] || command.arguments == ["app-server"])
    }

    @Test
    func makeAppServerRequestsUsesNullParamsForRateLimitsRead() throws {
        let requests = CodexAppServerClient.makeAppServerRequests(refreshToken: true)

        #expect(requests.count == 4)
        #expect(try JSONSerialization.jsonObject(with: Data(requests[3].utf8)) as? [String: Any] != nil)
        let rateLimitRequest = try #require(try JSONSerialization.jsonObject(with: Data(requests[3].utf8)) as? [String: Any])
        #expect(rateLimitRequest["method"] as? String == "account/rateLimits/read")
        #expect(rateLimitRequest.keys.contains("params"))
        #expect(rateLimitRequest["params"] is NSNull)
    }

    @Test
    func consumeOutputDataTreatsMissingRateLimitsPayloadAsPartialStatus() throws {
        let decoder = JSONDecoder()
        let state = AppServerSessionState()

        let accountLine = #"{"id":2,"result":{"account":{"email":"user@example.com","planType":"team"}}}"#
        let emptyRateLimitsLine = #"{"id":3,"result":{}}"#

        #expect(try consumeOutputData(Data((accountLine + "\n").utf8), decoder: decoder, state: state) == nil)
        let status = try consumeOutputData(Data((emptyRateLimitsLine + "\n").utf8), decoder: decoder, state: state)

        #expect(status?.email == "user@example.com")
        #expect(status?.planType == "team")
        #expect(status?.rateLimits == nil)
    }

    @Test
    func consumeOutputDataDropsIncompleteRateLimitWindowInsteadOfThrowing() throws {
        let decoder = JSONDecoder()
        let state = AppServerSessionState()

        let accountLine = #"{"id":2,"result":{"account":{"email":"user@example.com","planType":"team"}}}"#
        let partialRateLimitsLine = #"{"id":3,"result":{"rateLimits":{"planType":"team","primary":{"resetsAt":1776005472,"windowDurationMins":300},"secondary":{"usedPercent":18,"resetsAt":1776512418,"windowDurationMins":10080}}}}"#

        #expect(try consumeOutputData(Data((accountLine + "\n").utf8), decoder: decoder, state: state) == nil)
        let status = try consumeOutputData(Data((partialRateLimitsLine + "\n").utf8), decoder: decoder, state: state)

        #expect(status?.rateLimits?.primary == nil)
        #expect(status?.rateLimits?.secondary?.usedPercent == 18)
    }

    @Test
    func consumeOutputDataPreservesIntegerRateLimitFieldsFromEnvelope() throws {
        let decoder = JSONDecoder()
        let state = AppServerSessionState()

        let accountLine = #"{"id":2,"result":{"account":{"email":"user@example.com","planType":"team"}}}"#
        let rateLimitsLine = #"{"id":3,"result":{"rateLimits":{"planType":"team","primary":{"usedPercent":69,"resetsAt":2000000000,"windowDurationMins":300},"secondary":{"usedPercent":38,"resetsAt":2000500000,"windowDurationMins":10080}}}}"#

        #expect(try consumeOutputData(Data((accountLine + "\n").utf8), decoder: decoder, state: state) == nil)
        let status = try consumeOutputData(Data((rateLimitsLine + "\n").utf8), decoder: decoder, state: state)

        #expect(status?.rateLimits?.primary?.usedPercent == 69)
        #expect(status?.rateLimits?.primary?.resetsAt == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(status?.rateLimits?.secondary?.usedPercent == 38)
    }

    @Test
    func appServerStatusNeedsRetryWhenPrimaryWindowIsMissing() {
        let status = CodexAccountStatus(
            email: "user@example.com",
            planType: "team",
            rateLimits: CodexRateLimitSnapshot(
                limitID: "team",
                limitName: "Team",
                planType: "team",
                primary: nil,
                secondary: CodexRateLimitWindow(
                    usedPercent: 18,
                    resetsAt: Date(timeIntervalSince1970: 1_776_512_418),
                    windowDurationMinutes: 10_080
                ),
                fetchedAt: .now
            )
        )

        #expect(appServerStatusNeedsRetry(status))
    }

    @Test
    func consumeOutputDataWrapsDecodingFailuresInCodexAppServerError() throws {
        let decoder = JSONDecoder()
        let state = AppServerSessionState()
        let malformedLine = #"{"id":3}"#

        #expect(throws: CodexAppServerError.server("Codex returned an incomplete app-server response.")) {
            _ = try consumeOutputData(Data((malformedLine + "\n").utf8), decoder: decoder, state: state)
        }
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
