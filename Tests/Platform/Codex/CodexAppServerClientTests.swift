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
            usage: nil
        )
        let fullStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            usage: makeUsageSnapshot()
        )
        let reader = StatusSourceFixture(results: [
            .success(accountOnly),
            .success(fullStatus)
        ])
        let sleeper = SleepRecorder()
        let client = CodexAppServerClient(
            statusSource: reader.read,
            sleeper: sleeper.sleep
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false, true])
        #expect(await sleeper.recordedDurations() == [.seconds(1)])
        #expect(status.email == "user@example.com")
        #expect(status.usage == fullStatus.usage)
    }

    @Test
    func readCurrentAccountStatusRetriesAfterTransientFirstFailure() async throws {
        let fullStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            usage: makeUsageSnapshot()
        )
        let reader = StatusSourceFixture(results: [
            .failure(StatusReadError.transientFailure),
            .success(fullStatus)
        ])
        let sleeper = SleepRecorder()
        let client = CodexAppServerClient(
            statusSource: reader.read,
            sleeper: sleeper.sleep
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false, true])
        #expect(await sleeper.recordedDurations() == [.seconds(1)])
        #expect(status.usage == fullStatus.usage)
    }

    @Test
    func readCurrentAccountStatusRetriesTwiceAfterTransientRateLimitFailures() async throws {
        let fullStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            usage: makeUsageSnapshot()
        )
        let reader = StatusSourceFixture(results: [
            .failure(CodexAppServerError.server("failed to fetch codex rate limits")),
            .failure(CodexAppServerError.server("failed to fetch codex rate limits")),
            .success(fullStatus)
        ])
        let sleeper = SleepRecorder()
        let client = CodexAppServerClient(
            statusSource: reader.read,
            sleeper: sleeper.sleep
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false, true, true])
        #expect(await sleeper.recordedDurations() == [.seconds(1), .seconds(3)])
        #expect(status.usage == fullStatus.usage)
    }

    @Test
    func readCurrentAccountStatusRetriesWhenFirstResponseHasOnlyWeeklyRateLimits() async throws {
        let weeklyOnly = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            usage: UsageSnapshot.codex(
                planName: "plus",
                primary: nil,
                secondary: (usedPercent: 16, resetsAt: Date(timeIntervalSince1970: 1_776_512_418), durationMinutes: 10_080),
                fetchedAt: Date(timeIntervalSince1970: 1_776_000_000)
            )
        )
        let fullStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            usage: makeUsageSnapshot()
        )
        let reader = StatusSourceFixture(results: [
            .success(weeklyOnly),
            .success(fullStatus)
        ])
        let sleeper = SleepRecorder()
        let client = CodexAppServerClient(
            statusSource: reader.read,
            sleeper: sleeper.sleep
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false, true])
        #expect(await sleeper.recordedDurations() == [.seconds(1)])
        #expect(status.usage?.window(.session)?.usedPercent == 12)
        #expect(status.usage?.window(.weekly)?.usedPercent == 32)
    }

    @Test
    func readCurrentAccountStatusDoesNotRetryWhenResponseIsLegitimatelyZeroed() async throws {
        let zeroedStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "team",
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: (usedPercent: 0, resetsAt: .now.addingTimeInterval(3 * 60 * 60), durationMinutes: 300),
                secondary: (usedPercent: 0, resetsAt: .now.addingTimeInterval(6 * 24 * 60 * 60), durationMinutes: 10_080),
                fetchedAt: .now
            )
        )
        let reader = StatusSourceFixture(results: [
            .success(zeroedStatus)
        ])
        let sleeper = SleepRecorder()
        let client = CodexAppServerClient(
            statusSource: reader.read,
            sleeper: sleeper.sleep
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false])
        #expect(await sleeper.recordedDurations().isEmpty)
        #expect(status.usage?.window(.session)?.usedPercent == 0)
        #expect(status.usage?.window(.weekly)?.usedPercent == 0)
    }

    @Test
    func readCurrentAccountStatusMergesPartialRateLimitWindowsAcrossRetries() async throws {
        let weeklyOnly = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            usage: UsageSnapshot.codex(
                planName: "plus",
                primary: nil,
                secondary: (usedPercent: 18, resetsAt: Date(timeIntervalSince1970: 1_776_512_418), durationMinutes: 10_080),
                fetchedAt: Date(timeIntervalSince1970: 1_776_000_000)
            )
        )
        let sessionOnly = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            usage: UsageSnapshot.codex(
                planName: "plus",
                primary: (usedPercent: 69, resetsAt: Date(timeIntervalSince1970: 1_776_005_472), durationMinutes: 300),
                secondary: nil,
                fetchedAt: Date(timeIntervalSince1970: 1_776_000_100)
            )
        )
        let reader = StatusSourceFixture(results: [
            .success(weeklyOnly),
            .success(sessionOnly)
        ])
        let client = CodexAppServerClient(
            statusSource: reader.read,
            sleeper: { _ in }
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false, true])
        #expect(status.usage?.window(.session)?.usedPercent == 69)
        #expect(status.usage?.window(.weekly)?.usedPercent == 18)
    }

    @Test
    func readCurrentAccountStatusReturnsPartialStatusWhenRetryStillHasNoRateLimits() async throws {
        let firstStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            usage: nil
        )
        let secondStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "team",
            usage: nil
        )
        let reader = StatusSourceFixture(results: [
            .success(firstStatus),
            .success(secondStatus)
        ])
        let client = CodexAppServerClient(
            statusSource: reader.read,
            sleeper: { _ in }
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false, true])
        #expect(status.email == "user@example.com")
        #expect(status.planType == "team")
        #expect(status.usage == nil)
    }

    @Test
    func readCurrentAccountStatusReturnsFirstPartialStatusWhenRetryFails() async throws {
        let firstStatus = CodexAccountStatus(
            email: "user@example.com",
            planType: "plus",
            usage: nil
        )
        let reader = StatusSourceFixture(results: [
            .success(firstStatus),
            .failure(StatusReadError.transientFailure)
        ])
        let client = CodexAppServerClient(
            statusSource: reader.read,
            sleeper: { _ in }
        )

        let status = try await client.readCurrentAccountStatus()

        #expect(await reader.recordedRefreshTokens() == [false, true])
        #expect(status.email == "user@example.com")
        #expect(status.planType == "plus")
        #expect(status.usage == nil)
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
        #expect(status?.usage == nil)
    }

    @Test
    func consumeOutputDataDropsIncompleteRateLimitWindowInsteadOfFailing() throws {
        let decoder = JSONDecoder()
        let state = AppServerSessionState()

        let accountLine = #"{"id":2,"result":{"account":{"email":"user@example.com","planType":"team"}}}"#
        let partialRateLimitsLine = #"{"id":3,"result":{"rateLimits":{"planType":"team","primary":{"resetsAt":1776005472,"windowDurationMins":300},"secondary":{"usedPercent":18,"resetsAt":1776512418,"windowDurationMins":10080}}}}"#

        #expect(try consumeOutputData(Data((accountLine + "\n").utf8), decoder: decoder, state: state) == nil)
        let status = try consumeOutputData(Data((partialRateLimitsLine + "\n").utf8), decoder: decoder, state: state)

        #expect(status?.usage?.window(.session) == nil)
        #expect(status?.usage?.window(.weekly)?.usedPercent == 18)
    }

    @Test
    func consumeOutputDataPreservesIntegerRateLimitFieldsFromEnvelope() throws {
        let decoder = JSONDecoder()
        let state = AppServerSessionState()

        let accountLine = #"{"id":2,"result":{"account":{"email":"user@example.com","planType":"team"}}}"#
        let rateLimitsLine = #"{"id":3,"result":{"rateLimits":{"planType":"team","primary":{"usedPercent":69,"resetsAt":2000000000,"windowDurationMins":300},"secondary":{"usedPercent":38,"resetsAt":2000500000,"windowDurationMins":10080}}}}"#

        #expect(try consumeOutputData(Data((accountLine + "\n").utf8), decoder: decoder, state: state) == nil)
        let status = try consumeOutputData(Data((rateLimitsLine + "\n").utf8), decoder: decoder, state: state)

        #expect(status?.usage?.window(.session)?.usedPercent == 69)
        #expect(status?.usage?.window(.session)?.resetsAt == Date(timeIntervalSince1970: 2_000_000_000))
        #expect(status?.usage?.window(.weekly)?.usedPercent == 38)
    }

    @Test
    func consumeOutputDataPrefersCompleteCodexLimitByIDOverFallbackRateLimits() throws {
        let decoder = JSONDecoder()
        let state = AppServerSessionState()

        let accountLine = #"{"id":2,"result":{"account":{"email":"user@example.com","planType":"team"}}}"#
        let rateLimitsLine = #"{"id":3,"result":{"rateLimits":{"planType":"team","primary":{"usedPercent":90,"resetsAt":2000000000,"windowDurationMins":300},"secondary":{"usedPercent":80,"resetsAt":2000500000,"windowDurationMins":10080}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":"Codex","planType":"team","primary":{"usedPercent":21,"resetsAt":2000000000,"windowDurationMins":300},"secondary":{"usedPercent":34,"resetsAt":2000500000,"windowDurationMins":10080}}}}}"#

        #expect(try consumeOutputData(Data((accountLine + "\n").utf8), decoder: decoder, state: state) == nil)
        let status = try consumeOutputData(Data((rateLimitsLine + "\n").utf8), decoder: decoder, state: state)

        #expect(status?.usage?.window(.session)?.usedPercent == 21)
        #expect(status?.usage?.window(.weekly)?.usedPercent == 34)
    }

    @Test
    func consumeOutputDataReadsEachAvailableResetCreditExpiry() throws {
        let status = try readStatus(rateLimitsResult: #"{"rateLimits":{"primary":{"usedPercent":90,"windowDurationMins":300},"secondary":{"usedPercent":40,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":2,"credits":[{"id":"a","grantedAt":1,"resetType":"codexRateLimits","status":"available","expiresAt":2000900000},{"id":"b","grantedAt":1,"resetType":"codexRateLimits","status":"redeemed","expiresAt":2000100000},{"id":"c","grantedAt":1,"resetType":"unknown","status":"available","expiresAt":2000500000},{"id":"d","grantedAt":1,"resetType":"codexRateLimits","status":"available","expiresAt":null}]}}"#)

        #expect(status?.usage?.resetCredits?.availableCount == 2)
        #expect(status?.usage?.resetCredits?.credits?.map(\.expiresAt) == [
            Date(timeIntervalSince1970: 2_000_900_000),
            Date(timeIntervalSince1970: 2_000_500_000),
            nil,
        ])
        #expect(status?.usage?.resetCredits?.nextExpiry == Date(timeIntervalSince1970: 2_000_500_000))
    }

    @Test
    func consumeOutputDataKeepsTheResetCountWhenCodexOmitsCreditDetails() throws {
        let status = try readStatus(rateLimitsResult: #"{"rateLimits":{"primary":{"usedPercent":90,"windowDurationMins":300}},"rateLimitResetCredits":{"availableCount":3,"credits":null}}"#)

        #expect(status?.usage?.resetCredits == UsageResetCredits(availableCount: 3, credits: nil))
        #expect(status?.usage?.resetCredits?.nextExpiry == nil)
    }

    @Test
    func consumeOutputDataReadsOlderCodexWithoutResetCredits() throws {
        let status = try readStatus(rateLimitsResult: #"{"rateLimits":{"primary":{"usedPercent":90,"windowDurationMins":300}},"rateLimitResetCredits":null}"#)
        let olderStatus = try readStatus(rateLimitsResult: #"{"rateLimits":{"primary":{"usedPercent":90,"windowDurationMins":300}}}"#)

        #expect(status?.usage?.window(.session)?.usedPercent == 90)
        #expect(status?.usage?.resetCredits == nil)
        #expect(olderStatus?.usage?.window(.session)?.usedPercent == 90)
        #expect(olderStatus?.usage?.resetCredits == nil)
    }

    @Test(arguments: [
        ("reset", CodexResetCreditOutcome.reset),
        ("nothingToReset", .nothingToReset),
        ("noCredit", .noCredit),
        ("alreadyRedeemed", .alreadyRedeemed),
        ("somethingNew", .unrecognized),
    ])
    func consumeResetCreditSendsTheIdempotencyKeyAndReadsTheOutcome(rawOutcome: String, outcome: CodexResetCreditOutcome) async throws {
        let fixture = try AppServerFixture(output: #"{"id":2,"result":{"outcome":"\#(rawOutcome)"}}"#)
        defer { fixture.remove() }
        let key = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00CF4FC964FF")!

        let result = try await fixture.client.consumeResetCredit(idempotencyKey: key)

        #expect(result == outcome)
        let requests = try fixture.requests()
        #expect(requests.contains(#""method":"initialize""#))
        #expect(requests.contains(#"{"method":"account/rateLimitResetCredit/consume","id":2,"params":{"idempotencyKey":"6F9619FF-8B86-D011-B42D-00CF4FC964FF"}}"#))
    }

    @Test
    func consumeResetCreditSurfacesCodexErrors() async throws {
        let fixture = try AppServerFixture(output: #"{"id":2,"error":{"code":-32600,"message":"not signed in"}}"#)
        defer { fixture.remove() }

        await #expect(throws: CodexAppServerError.server("not signed in")) {
            _ = try await fixture.client.consumeResetCredit(idempotencyKey: UUID())
        }
    }

    @Test
    func consumeResetCreditFailsWhenCodexExitsWithoutAnswering() async throws {
        let fixture = try AppServerFixture(output: #"{"id":1,"result":{}}"#)
        defer { fixture.remove() }

        await #expect(throws: CodexAppServerError.server("Codex app-server ended before using the reset.")) {
            _ = try await fixture.client.consumeResetCredit(idempotencyKey: UUID())
        }
    }

    @Test
    func readSavedAccountStatusTreatsPrematureExitBeforeRateLimitResponseAsSessionFailure() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("CodexPill-AppServerClientTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let requestsFile = directory.appendingPathComponent("requests.jsonl")
        let script = directory.appendingPathComponent("codex-fixture.sh")
        let scriptBody = """
        #!/bin/sh
        head -n 4 > "\(requestsFile.path)"
        printf '%s\\n' '{"id":2,"result":{"account":{"email":"user@example.com","planType":"team"}}}'
        exit 0
        """
        try Data(scriptBody.utf8).write(to: script)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let client = CodexAppServerClient(environment: ["CODEX_CLI_PATH": script.path])

        let read = await client.readSavedAccountStatus(authData: Data("{}".utf8))

        #expect(throws: CodexAppServerError.server("Codex app-server ended before returning rate limits.")) {
            _ = try read.status.get()
        }
        #expect(read.rotatedAuthData == nil)

        let requests = try String(contentsOf: requestsFile, encoding: .utf8)
        #expect(requests.contains(#""method":"initialize""#))
        #expect(requests.contains(#""method":"initialized""#))
        #expect(requests.contains(#""method":"account/read""#))
        #expect(requests.contains(#""method":"account/rateLimits/read""#))
    }

    @Test(arguments: [true, false])
    func readSavedAccountStatusReturnsAuthRotatedInsideIsolatedHome(rotates: Bool) async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("CodexPill-AppServerClientTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let requestsFile = directory.appendingPathComponent("requests.jsonl")
        let script = directory.appendingPathComponent("codex-rotation-fixture.sh")
        let rotation = rotates ? #"printf '%s' '{"tokens":"rotated"}' > "$CODEX_HOME/auth.json""# : ""
        let scriptBody = """
        #!/bin/sh
        head -n 4 > "\(requestsFile.path)"
        \(rotation)
        exit 0
        """
        try Data(scriptBody.utf8).write(to: script)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let client = CodexAppServerClient(environment: ["CODEX_CLI_PATH": script.path])

        let read = await client.readSavedAccountStatus(authData: Data(#"{"tokens":"original"}"#.utf8))

        #expect(read.rotatedAuthData == (rotates ? Data(#"{"tokens":"rotated"}"#.utf8) : nil))
        let requests = try String(contentsOf: requestsFile, encoding: .utf8)
        #expect(requests.contains(#""method":"account/read","id":2,"params":{"refreshToken":false}"#))
    }

    @Test
    func savedAccountReadKeepsLocalFailureClassificationWhenSharedSessionExitsNonZero() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("CodexPill-AppServerClientTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let script = directory.appendingPathComponent("codex-failure-fixture.sh")
        let scriptBody = """
        #!/bin/sh
        printf 'local app-server failure\\n' >&2
        exit 9
        """
        try Data(scriptBody.utf8).write(to: script)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let client = CodexAppServerClient(environment: ["CODEX_CLI_PATH": script.path])

        let read = await client.readSavedAccountStatus(authData: Data(#"{"tokens":"original"}"#.utf8))

        #expect(throws: CodexAppServerError.server("local app-server failure")) {
            _ = try read.status.get()
        }
    }

    @Test
    func consumeOutputDataIgnoresNotificationFramesWithoutIDs() throws {
        let decoder = JSONDecoder()
        let state = AppServerSessionState()

        let notificationLine = #"{"method":"initialized","params":{}}"#
        let accountLine = #"{"id":2,"result":{"account":{"email":"user@example.com","planType":"team"}}}"#

        #expect(try consumeOutputData(Data((notificationLine + "\n").utf8), decoder: decoder, state: state) == nil)
        #expect(try consumeOutputData(Data((accountLine + "\n").utf8), decoder: decoder, state: state) == nil)
        #expect(state.partialStatus()?.email == "user@example.com")
    }

    @Test
    func consumeOutputDataSurfacesJsonRPCErrorMessages() throws {
        let decoder = JSONDecoder()
        let state = AppServerSessionState()
        let errorLine = #"{"id":3,"error":{"code":-32603,"message":"failed to fetch codex rate limits: network unavailable"}}"#

        #expect(throws: CodexAppServerError.server("failed to fetch codex rate limits: network unavailable")) {
            _ = try consumeOutputData(Data((errorLine + "\n").utf8), decoder: decoder, state: state)
        }
    }

    @Test
    func appServerStatusNeedsRetryWhenPrimaryWindowIsMissing() {
        let status = CodexAccountStatus(
            email: "user@example.com",
            planType: "team",
            usage: UsageSnapshot.codex(
                planName: "team",
                primary: nil,
                secondary: (usedPercent: 18, resetsAt: Date(timeIntervalSince1970: 1_776_512_418), durationMinutes: 10_080),
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

    private func readStatus(rateLimitsResult: String) throws -> CodexAccountStatus? {
        let state = AppServerSessionState()
        let lines = [
            #"{"id":2,"result":{"account":{"email":"user@example.com","planType":"team"}}}"#,
            #"{"id":3,"result":"# + rateLimitsResult + "}",
        ]
        return try consumeOutputData(Data((lines.joined(separator: "\n") + "\n").utf8), decoder: JSONDecoder(), state: state)
    }

    private func makeUsageSnapshot() -> UsageSnapshot {
        UsageSnapshot.codex(
            planName: "plus",
            primary: (usedPercent: 12, resetsAt: Date(timeIntervalSince1970: 1_776_005_472), durationMinutes: 300),
            secondary: (usedPercent: 32, resetsAt: Date(timeIntervalSince1970: 1_776_512_418), durationMinutes: 10_080),
            fetchedAt: Date(timeIntervalSince1970: 1_776_000_000)
        )
    }
}

private actor StatusSourceFixture {
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

/// A stand-in `codex app-server` that records the requests it receives and prints one canned line.
private struct AppServerFixture {
    let directory: URL
    let client: CodexAppServerClient
    private let requestsFile: URL

    init(output: String) throws {
        let fileManager = FileManager.default
        directory = fileManager.temporaryDirectory
            .appendingPathComponent("CodexPill-AppServerClientTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        requestsFile = directory.appendingPathComponent("requests.jsonl")
        let script = directory.appendingPathComponent("codex-fixture.sh")
        let scriptBody = """
        #!/bin/sh
        head -n 3 > "\(requestsFile.path)"
        printf '%s\\n' '\(output)'
        exit 0
        """
        try Data(scriptBody.utf8).write(to: script)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        client = CodexAppServerClient(environment: ["CODEX_CLI_PATH": script.path])
    }

    func requests() throws -> String {
        try String(contentsOf: requestsFile, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
