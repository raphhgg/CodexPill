import CryptoKit
import Foundation

struct CommandResult: Equatable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
}

protocol CommandRunner {
    func run(executableURL: URL, arguments: [String]) async throws -> CommandResult
}

struct ProcessCommandRunner: CommandRunner {
    func run(executableURL: URL, arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { process in
                let result = CommandResult(
                    terminationStatus: process.terminationStatus,
                    standardOutput: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                    standardError: errorPipe.fileHandleForReading.readDataToEndOfFile()
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

protocol AccountSnapshotLocator {
    func snapshotURL(for account: CodexAccount) -> URL
}

extension AccountRepository: AccountSnapshotLocator {}

struct SSHRemoteHostClient: RemoteHostClient {
    private static let responseTimeout: Duration = .seconds(10)
    private static let missingRemoteAuthExitCode: Int32 = 17
    private static let appServerListenAddress = "ws://127.0.0.1:9234"
    private static let appServerProcessPattern = "codex app-server --listen ws://127.0.0.1:9234"
    private let snapshotLocator: AccountSnapshotLocator
    private let commandRunner: CommandRunner
    private let sshExecutableURL: URL
    private let scpExecutableURL: URL
    private let appServerReadinessProbeDelays: [Duration]

    init(
        snapshotLocator: AccountSnapshotLocator,
        commandRunner: CommandRunner = ProcessCommandRunner(),
        sshExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        scpExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/scp"),
        appServerReadinessProbeDelays: [Duration] = [.zero, .seconds(1), .seconds(2)]
    ) {
        self.snapshotLocator = snapshotLocator
        self.commandRunner = commandRunner
        self.sshExecutableURL = sshExecutableURL
        self.scpExecutableURL = scpExecutableURL
        self.appServerReadinessProbeDelays = appServerReadinessProbeDelays
    }

    func testConnection(to host: RemoteHost) async throws {
        let result = try await commandRunner.run(
            executableURL: sshExecutableURL,
            arguments: sshArguments(
                host: host,
                command: "command -v codex >/dev/null 2>&1 && codex app-server --help >/dev/null 2>&1 && mkdir -p .codexpill/snapshots .codex"
            )
        )

        guard result.terminationStatus == 0 else {
            throw remoteCommandFailure(result)
        }
    }

    func installationState(for account: CodexAccount, on host: RemoteHost) async throws -> RemoteHostAccountInstallationState {
        let result = try await commandRunner.run(
            executableURL: sshExecutableURL,
            arguments: sshArguments(
                host: host,
                command: "test -f \(quoted(".codexpill/snapshots/\(account.snapshotFileName)"))"
            )
        )

        switch result.terminationStatus {
        case 0:
            return .installed
        case 1:
            return .missing
        default:
            throw remoteCommandFailure(result)
        }
    }

    func installAccount(_ account: CodexAccount, on host: RemoteHost) async throws {
        try await ensureRemoteDirectories(on: host)

        let result = try await commandRunner.run(
            executableURL: scpExecutableURL,
            arguments: baseRemoteCommandOptions() + [
                snapshotLocator.snapshotURL(for: account).path,
                "\(host.destination):.codexpill/snapshots/\(account.snapshotFileName)"
            ]
        )

        guard result.terminationStatus == 0 else {
            throw remoteCommandFailure(result)
        }
    }

    func switchToAccount(_ account: CodexAccount, on host: RemoteHost) async throws {
        try await ensureRemoteDirectories(on: host)

        let result = try await commandRunner.run(
            executableURL: sshExecutableURL,
            arguments: sshArguments(
                host: host,
                command: "cp \(quoted(".codexpill/snapshots/\(account.snapshotFileName)")) \(quoted(".codex/auth.json"))"
            )
        )

        guard result.terminationStatus == 0 else {
            throw remoteCommandFailure(result)
        }
    }

    func refreshCodexAppServer(on host: RemoteHost) async throws {
        let pids = try await appServerProcessIDs(on: host)
        if !pids.isEmpty {
            try await terminateAppServerProcesses(pids, on: host)
        }

        let startResult = try await commandRunner.run(
            executableURL: sshExecutableURL,
            arguments: sshArguments(
                host: host,
                command: "nohup codex app-server --listen \(Self.appServerListenAddress) >/tmp/codex-app-server.log 2>&1 </dev/null &"
            )
        )

        guard startResult.terminationStatus == 0 else {
            throw remoteCommandFailure(startResult)
        }

        for (index, delay) in appServerReadinessProbeDelays.enumerated() {
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }

            let readinessResult = try await commandRunner.run(
                executableURL: sshExecutableURL,
                arguments: sshArguments(
                    host: host,
                    command: "if command -v ss >/dev/null 2>&1; then ss -ltnp | grep '127.0.0.1:9234'; else pgrep -f '\(Self.appServerProcessPattern)' >/dev/null; fi"
                )
            )

            if readinessResult.terminationStatus == 0 {
                return
            }

            if index == appServerReadinessProbeDelays.count - 1 {
                throw remoteCommandFailure(readinessResult)
            }
        }
    }

    func readCurrentAccountStatus(on host: RemoteHost) async throws -> CodexAccountStatus {
        let attempts: [(refreshToken: Bool, delay: Duration)] = [
            (false, .zero),
            (true, .seconds(1))
        ]

        var latestPartialStatus: CodexAccountStatus?
        var latestError: Error?

        for (index, attempt) in attempts.enumerated() {
            if attempt.delay > .zero {
                try? await Task.sleep(for: attempt.delay)
            }

            do {
                let status = try await readAccountStatus(on: host, refreshToken: attempt.refreshToken)
                latestPartialStatus = mergeStatuses(previous: latestPartialStatus, current: status)
            } catch {
                latestError = error

                if index < attempts.count - 1 {
                    continue
                }
                break
            }

            guard shouldRetry(status: latestPartialStatus, attemptIndex: index, totalAttempts: attempts.count) else {
                return try await enrichStatusWithRemoteAuthDataIfAvailable(latestPartialStatus ?? CodexAccountStatus(email: nil, planType: nil, rateLimits: nil), on: host)
            }
        }

        if let latestPartialStatus {
            return try await enrichStatusWithRemoteAuthDataIfAvailable(latestPartialStatus, on: host)
        }

        if let latestError {
            throw latestError
        }

        throw CocoaError(.coderReadCorrupt)
    }

    private func ensureRemoteDirectories(on host: RemoteHost) async throws {
        let result = try await commandRunner.run(
            executableURL: sshExecutableURL,
            arguments: sshArguments(
                host: host,
                command: "mkdir -p .codexpill/snapshots .codex"
            )
        )

        guard result.terminationStatus == 0 else {
            throw remoteCommandFailure(result)
        }
    }

    private func sshArguments(host: RemoteHost, command: String) -> [String] {
        baseRemoteCommandOptions() + [host.destination, command]
    }

    private func baseRemoteCommandOptions() -> [String] {
        [
            "-T",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ConnectionAttempts=1"
        ]
    }

    private func terminateAppServerProcesses(_ pids: [String], on host: RemoteHost) async throws {
        let killResult = try await commandRunner.run(
            executableURL: sshExecutableURL,
            arguments: sshArguments(
                host: host,
                command: "kill -9 \(pids.joined(separator: " "))"
            )
        )

        guard killResult.terminationStatus != 0 else { return }

        let remainingPIDs = try await appServerProcessIDs(on: host)
        let remainingTargetPIDs = remainingPIDs.filter { pids.contains($0) }
        guard !remainingTargetPIDs.isEmpty else { return }

        throw remoteCommandFailure(killResult)
    }

    private func quoted(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appServerProcessIDs(on host: RemoteHost) async throws -> [String] {
        let result = try await commandRunner.run(
            executableURL: sshExecutableURL,
            arguments: sshArguments(
                host: host,
                command: "pgrep -f '\(Self.appServerProcessPattern)' || true"
            )
        )

        guard result.terminationStatus == 0 else {
            throw remoteCommandFailure(result)
        }

        return String(decoding: result.standardOutput, as: UTF8.self)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private func remoteCommandFailure(_ result: CommandResult) -> RemoteHostClientError {
        let message = String(decoding: result.standardError, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .commandFailed(message.isEmpty ? "Remote command exited with code \(result.terminationStatus)." : message)
    }

    private func readAccountStatus(on host: RemoteHost, refreshToken: Bool) async throws -> CodexAccountStatus {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let inputPipe = Pipe()
            let inputHandle = inputPipe.fileHandleForWriting
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let state = AppServerSessionState()

            let finish: @Sendable (Result<CodexAccountStatus, Error>) -> Void = { result in
                guard state.markFinished() else { return }
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                try? inputHandle.close()
                if process.isRunning {
                    process.terminate()
                }
                continuation.resume(with: result)
            }

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                do {
                    if let snapshot = try consumeOutputData(data, decoder: decoder, state: state) {
                        finish(.success(snapshot))
                    }
                } catch {
                    finish(.failure(error))
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                state.appendErrorOutput(data)
            }

            process.executableURL = sshExecutableURL
            process.arguments = sshArguments(host: host, command: "codex app-server")
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { process in
                let trailingOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if !trailingOutput.isEmpty {
                    do {
                        if let snapshot = try consumeOutputData(trailingOutput, decoder: decoder, state: state) {
                            finish(.success(snapshot))
                            return
                        }
                    } catch {
                        finish(.failure(error))
                        return
                    }
                }

                let trailingError = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if !trailingError.isEmpty {
                    state.appendErrorOutput(trailingError)
                }

                if process.terminationStatus == 0, let partialStatus = state.partialStatus() {
                    finish(.success(partialStatus))
                    return
                }

                guard process.terminationStatus != 0 else { return }
                finish(.failure(CodexAppServerError.remoteConnectionFailed(
                    remoteFailureMessage(stderr: state.capturedStderr(), terminationStatus: Int(process.terminationStatus))
                )))
            }

            do {
                try process.run()
                let payload = CodexAppServerClient.makeAppServerRequests(refreshToken: refreshToken).joined(separator: "\n") + "\n"
                inputHandle.write(Data(payload.utf8))

                Task {
                    try? await Task.sleep(for: Self.responseTimeout)
                    if let partialStatus = state.partialStatus() {
                        finish(.success(partialStatus))
                        return
                    }
                    finish(.failure(appServerFailure(
                        stderr: state.capturedStderr(),
                        terminationStatus: nil,
                        timedOut: true
                    )))
                }
            } catch {
                finish(.failure(error))
            }
        }
    }

    private func shouldRetry(status: CodexAccountStatus?, attemptIndex: Int, totalAttempts: Int) -> Bool {
        guard attemptIndex < totalAttempts - 1 else { return false }
        if appServerStatusNeedsRetry(status) {
            return true
        }
        return appServerRateLimitsLookSuspiciouslyZeroed(status?.rateLimits)
    }

    private func mergeStatuses(previous: CodexAccountStatus?, current: CodexAccountStatus) -> CodexAccountStatus {
        mergeAppServerStatuses(previous: previous, current: current)
    }

    private func enrichStatusWithRemoteAuthDataIfAvailable(
        _ status: CodexAccountStatus,
        on host: RemoteHost
    ) async throws -> CodexAccountStatus {
        guard let authData = try await readRemoteAuthData(on: host) else {
            return status
        }

        return mergeStatuses(
            previous: status,
            current: CodexAccountStatus(
                email: CodexAuthDataParser.email(from: authData),
                planType: CodexAuthDataParser.planType(from: authData),
                rateLimits: nil,
                stableAccountID: CodexAuthDataParser.stableAccountID(from: authData),
                authPrincipalIdentity: CodexAuthDataParser.authPrincipalIdentity(from: authData),
                workspaceIdentity: CodexAuthDataParser.workspaceIdentity(from: authData),
                snapshotFingerprint: snapshotFingerprint(for: authData)
            )
        )
    }

    private func readRemoteAuthData(on host: RemoteHost) async throws -> Data? {
        let result = try await commandRunner.run(
            executableURL: sshExecutableURL,
            arguments: sshArguments(
                host: host,
                command: "if [ ! -f \(quoted(".codex/auth.json")) ]; then exit \(Self.missingRemoteAuthExitCode); fi\ncat \(quoted(".codex/auth.json"))"
            )
        )

        switch result.terminationStatus {
        case 0:
            return result.standardOutput.isEmpty ? nil : result.standardOutput
        case Self.missingRemoteAuthExitCode:
            return nil
        default:
            let message = String(decoding: result.standardError, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RemoteHostClientError.authReadFailed(
                message.isEmpty ? "Remote auth verification failed with code \(result.terminationStatus)." : message
            )
        }
    }

    private func snapshotFingerprint(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func remoteFailureMessage(stderr: String?, terminationStatus: Int) -> String {
        if let stderr, !stderr.isEmpty {
            return stderr
        }

        return "Remote Codex app-server exited with code \(terminationStatus)."
    }
}
