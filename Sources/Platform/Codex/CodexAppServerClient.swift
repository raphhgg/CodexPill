import Foundation

final class CodexAppServerClient {
    typealias StatusSource = @Sendable (_ refreshToken: Bool) async throws -> CodexAccountStatus
    typealias AppServerStatusSource = @Sendable (_ refreshToken: Bool) async throws -> CodexAppServerStatus
    typealias Sleeper = @Sendable (_ duration: Duration) async -> Void

    private let statusSource: AppServerStatusSource
    private let sleeper: Sleeper
    private let configuration: CodexAppServerConfiguration
    private let mapper: RUsageAccountStatusMapper

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let configuration = CodexAppServerConfiguration.live(environment: environment)
        self.configuration = configuration
        statusSource = { refreshToken in
            try await Self.readAppServerStatus(
                configuration: configuration,
                refreshToken: refreshToken,
                requireRateLimitResponse: false
            )
        }
        sleeper = { duration in
            try? await Task.sleep(for: duration)
        }
        mapper = RUsageAccountStatusMapper()
    }

    init(
        statusSource: @escaping StatusSource,
        sleeper: @escaping Sleeper
    ) {
        self.configuration = CodexAppServerConfiguration(
            command: CodexCLICommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["codex", "app-server"]
            ),
            environment: nil
        )
        self.statusSource = { refreshToken in
            let status = try await statusSource(refreshToken)
            return CodexAppServerStatus(
                account: CodexAppServerAccount(
                    email: status.email,
                    planType: status.planType,
                    stableAccountID: status.stableAccountID,
                    authPrincipalIdentity: status.authPrincipalIdentity,
                    workspaceIdentity: status.workspaceIdentity,
                    snapshotFingerprint: status.snapshotFingerprint
                ),
                rateLimits: status.usage.map { usage in
                    CodexAppServerRateLimits(
                        limitID: nil,
                        limitName: nil,
                        planType: usage.planName,
                        primary: usage.codexSlots.primary.map(Self.appServerWindow),
                        secondary: usage.codexSlots.secondary.map(Self.appServerWindow),
                        resetCredits: usage.resetCredits,
                        credits: usage.credits,
                        fetchedAt: usage.fetchedAt
                    )
                }
            )
        }
        self.sleeper = sleeper
        mapper = RUsageAccountStatusMapper()
    }

    private static func appServerWindow(from window: UsageWindow) -> CodexAppServerRateLimitWindow {
        CodexAppServerRateLimitWindow(
            usedPercent: window.usedPercent,
            resetsAt: window.resetsAt,
            windowDurationMinutes: window.durationMinutes
        )
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        let attempts: [(refreshToken: Bool, delay: Duration)] = [
            (false, .zero),
            (true, .seconds(1)),
            (true, .seconds(3))
        ]

        var latestPartialStatus: CodexAccountStatus?
        var latestError: Error?

        for (index, attempt) in attempts.enumerated() {
            if attempt.delay > .zero {
                await sleeper(attempt.delay)
            }

            do {
                let status = mapper.status(from: try await statusSource(attempt.refreshToken))
                latestPartialStatus = mergeStatuses(previous: latestPartialStatus, current: status)

                guard shouldRetry(status: latestPartialStatus, attemptIndex: index, totalAttempts: attempts.count) else {
                    return latestPartialStatus ?? status
                }
            } catch {
                latestError = error

                if let latestPartialStatus {
                    return latestPartialStatus
                }

                guard index < attempts.count - 1 else {
                    throw error
                }

                guard shouldRetry(error: error, attemptIndex: index, totalAttempts: attempts.count) else {
                    throw error
                }
            }
        }

        if let latestPartialStatus {
            return latestPartialStatus
        }

        throw latestError ?? CocoaError(.coderReadCorrupt)
    }

    func consumeResetCredit(idempotencyKey: UUID) async throws -> CodexResetCreditOutcome {
        try await CodexAppServerSessionRunner().consumeResetCredit(command: CodexResetCreditConsumeCommand(
            executableURL: configuration.command.executableURL,
            arguments: configuration.command.arguments,
            environment: configuration.environment,
            timeout: configuration.responseTimeout,
            clientInfo: configuration.clientInfo,
            idempotencyKey: idempotencyKey,
            failure: { stderr, terminationStatus, timedOut in
                appServerFailure(stderr: stderr, terminationStatus: terminationStatus, timedOut: timedOut)
            }
        ))
    }

    private static func readAppServerStatus(
        configuration: CodexAppServerConfiguration,
        refreshToken: Bool,
        requireRateLimitResponse: Bool
    ) async throws -> CodexAppServerStatus {
        try await CodexAppServerSessionRunner().readAccountStatus(command: CodexAppServerSessionCommand(
            executableURL: configuration.command.executableURL,
            arguments: configuration.command.arguments,
            environment: configuration.environment,
            timeout: configuration.responseTimeout,
            refreshToken: refreshToken,
            clientInfo: configuration.clientInfo,
            requireRateLimitResponse: requireRateLimitResponse,
            failure: { stderr, terminationStatus, timedOut in
                appServerFailure(stderr: stderr, terminationStatus: terminationStatus, timedOut: timedOut)
            }
        ))
    }

    private func shouldRetry(status: CodexAccountStatus?, attemptIndex: Int, totalAttempts: Int) -> Bool {
        guard attemptIndex < totalAttempts - 1 else { return false }
        guard attemptIndex == 0 else { return false }
        return appServerStatusNeedsRetry(status)
    }

    private func shouldRetry(error: Error, attemptIndex: Int, totalAttempts: Int) -> Bool {
        guard attemptIndex < totalAttempts - 1 else { return false }
        guard attemptIndex > 0 else { return true }
        return isRateLimitReadFailure(error)
    }

    private func isRateLimitReadFailure(_ error: Error) -> Bool {
        guard case .server(let message) = error as? CodexAppServerError else {
            return false
        }
        let normalizedMessage = message.lowercased()
        return normalizedMessage.contains("rate limit") || normalizedMessage.contains("ratelimit")
    }

    private func mergeStatuses(previous: CodexAccountStatus?, current: CodexAccountStatus) -> CodexAccountStatus {
        mergeAppServerStatuses(previous: previous, current: current)
    }

    static func makeAppServerCommand(environment: [String: String]) -> CodexCLICommand {
        CodexAppServerConfiguration.makeAppServerCommand(environment: environment)
    }

    static func makeAppServerRequests(refreshToken: Bool) -> [String] {
        CodexAppServerSession.makeRequests(refreshToken: refreshToken)
    }
}

extension CodexAppServerClient: CodexAccountStatusClient {}
extension CodexAppServerClient: CodexResetCreditClient {}
