import Foundation

final class CodexAppServerClient {
    typealias StatusSource = @Sendable (_ refreshToken: Bool) async throws -> CodexAccountStatus
    typealias AppServerStatusSource = @Sendable (_ refreshToken: Bool) async throws -> CodexAppServerStatus
    typealias Sleeper = @Sendable (_ duration: Duration) async -> Void

    private let statusSource: AppServerStatusSource
    private let sleeper: Sleeper
    private let configuration: CodexAppServerConfiguration
    private let mapper: CodexPillAccountStatusMapper

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let configuration = CodexAppServerConfiguration.live(environment: environment)
        let runner = CodexAppServerProcessRunner()
        self.configuration = configuration
        statusSource = { refreshToken in
            try await runner.readAccountStatus(
                configuration: configuration,
                refreshToken: refreshToken,
                requireRateLimitResponse: false
            )
        }
        sleeper = { duration in
            try? await Task.sleep(for: duration)
        }
        mapper = CodexPillAccountStatusMapper()
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
                rateLimits: status.rateLimits.map { CodexAppServerRateLimits(
                    limitID: $0.limitID,
                    limitName: $0.limitName,
                    planType: $0.planType,
                    primary: $0.primary.map { CodexAppServerRateLimitWindow(
                        usedPercent: $0.usedPercent,
                        resetsAt: $0.resetsAt,
                        windowDurationMinutes: $0.windowDurationMinutes
                    ) },
                    secondary: $0.secondary.map { CodexAppServerRateLimitWindow(
                        usedPercent: $0.usedPercent,
                        resetsAt: $0.resetsAt,
                        windowDurationMinutes: $0.windowDurationMinutes
                    ) },
                    fetchedAt: $0.fetchedAt
                ) }
            )
        }
        self.sleeper = sleeper
        mapper = CodexPillAccountStatusMapper()
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

    func readSavedAccountStatus(authData: Data) async throws -> CodexAccountStatus {
        let session = try IsolatedCodexHomeSession.create()
        defer { try? session.cleanup() }

        try authData.write(to: session.authFile, options: .atomic)

        let runner = CodexAppServerProcessRunner()
        let status = try await runner.readAccountStatus(
            configuration: CodexAppServerConfiguration(
                command: configuration.command,
                environment: Self.isolatedAppServerEnvironment(command: configuration.command, session: session),
                responseTimeout: configuration.responseTimeout,
                clientInfo: configuration.clientInfo
            ),
            refreshToken: true,
            requireRateLimitResponse: true
        )
        return mapper.status(from: status)
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

    private static func isolatedAppServerEnvironment(
        command: CodexCLICommand,
        session: IsolatedCodexHomeSession,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        let executableDirectory = command.executableURL.deletingLastPathComponent().path
        environment["CODEX_HOME"] = session.rootDirectory.path
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        environment["LOGNAME"] = NSUserName()
        environment["PATH"] = "\(executableDirectory):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["TMPDIR"] = session.tempDirectory.path
        environment["USER"] = NSUserName()
        return environment
    }
}

extension CodexAppServerClient: CodexAccountStatusClient {}
extension CodexAppServerClient: SavedCodexAccountStatusClient {}
