import Foundation

struct CommandResult: Equatable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
}

protocol CommandRunning {
    func run(executableURL: URL, arguments: [String]) async throws -> CommandResult
}

struct ProcessCommandRunner: CommandRunning {
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

protocol AccountSnapshotLocating {
    func snapshotURL(for account: CodexAccount) -> URL
}

extension AccountRepository: AccountSnapshotLocating {}

struct SSHRemoteHostClient: RemoteHostSwitching {
    private static let responseTimeout: Duration = .seconds(10)
    private let snapshotLocator: AccountSnapshotLocating
    private let commandRunner: CommandRunning
    private let sshExecutableURL: URL
    private let scpExecutableURL: URL

    init(
        snapshotLocator: AccountSnapshotLocating,
        commandRunner: CommandRunning = ProcessCommandRunner(),
        sshExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        scpExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/scp")
    ) {
        self.snapshotLocator = snapshotLocator
        self.commandRunner = commandRunner
        self.sshExecutableURL = sshExecutableURL
        self.scpExecutableURL = scpExecutableURL
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

                guard shouldRetry(status: latestPartialStatus, attemptIndex: index, totalAttempts: attempts.count) else {
                    return latestPartialStatus ?? status
                }
            } catch {
                latestError = error

                guard index < attempts.count - 1 else {
                    if let latestPartialStatus {
                        return latestPartialStatus
                    }
                    throw error
                }
            }
        }

        if let latestPartialStatus {
            return latestPartialStatus
        }

        throw latestError ?? CocoaError(.coderReadCorrupt)
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
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ConnectionAttempts=1"
        ]
    }

    private func quoted(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
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
                try? inputHandle.close()

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
        guard let status else { return true }
        return status.email != nil && status.rateLimits == nil
    }

    private func mergeStatuses(previous: CodexAccountStatus?, current: CodexAccountStatus) -> CodexAccountStatus {
        CodexAccountStatus(
            email: current.email ?? previous?.email,
            planType: current.planType ?? previous?.planType,
            rateLimits: current.rateLimits ?? previous?.rateLimits
        )
    }

    private func remoteFailureMessage(stderr: String?, terminationStatus: Int) -> String {
        if let stderr, !stderr.isEmpty {
            return stderr
        }

        return "Remote Codex app-server exited with code \(terminationStatus)."
    }
}
