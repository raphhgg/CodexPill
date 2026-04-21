import Foundation

protocol LocalCommandRunning {
    func run(executableURL: URL, arguments: [String], environment: [String: String]) async throws -> CommandResult
}

struct LocalProcessCommandRunner: LocalCommandRunning {
    func run(executableURL: URL, arguments: [String], environment: [String: String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = environment
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

enum CodexLoginCaptureError: LocalizedError, Equatable {
    case loginFailed(String)
    case missingCapturedAuth
    case missingDeviceAuthPrompt

    var errorDescription: String? {
        switch self {
        case .loginFailed(let message):
            message
        case .missingCapturedAuth:
            "Codex did not produce an auth.json file in the isolated CODEX_HOME."
        case .missingDeviceAuthPrompt:
            "Codex did not print a device-auth URL."
        }
    }
}

struct CodexDeviceAuthPrompt: Equatable {
    let verificationURL: URL
    let userCode: String?
}

protocol CodexDeviceAuthCaptureHandling: AnyObject {
    func deviceAuthPrompt() async -> CodexDeviceAuthPrompt
    func waitForCapturedAuth() async throws -> Data
    func cancel() async
    func cleanup() async throws
}

protocol CodexDeviceAuthCapturing {
    func beginDeviceAuth(in session: IsolatedCodexHomeSession) async throws -> any CodexDeviceAuthCaptureHandling
}

actor CodexDeviceAuthCaptureSession: CodexDeviceAuthCaptureHandling {
    let prompt: CodexDeviceAuthPrompt

    private let process: Process
    private let isolatedSession: IsolatedCodexHomeSession
    private let authFile: URL
    private let terminationTask: Task<CommandResult, Error>

    init(
        prompt: CodexDeviceAuthPrompt,
        process: Process,
        isolatedSession: IsolatedCodexHomeSession,
        authFile: URL,
        terminationTask: Task<CommandResult, Error>
    ) {
        self.prompt = prompt
        self.process = process
        self.isolatedSession = isolatedSession
        self.authFile = authFile
        self.terminationTask = terminationTask
    }

    func waitForCapturedAuth() async throws -> Data {
        let result = try await terminationTask.value

        guard result.terminationStatus == 0 else {
            throw CodexLoginCaptureError.loginFailed(
                CodexLoginCaptureClient.commandFailureMessage(
                    standardError: result.standardError,
                    standardOutput: result.standardOutput,
                    terminationStatus: result.terminationStatus
                )
            )
        }

        guard FileManager.default.fileExists(atPath: authFile.path) else {
            throw CodexLoginCaptureError.missingCapturedAuth
        }

        return try Data(contentsOf: authFile)
    }

    func cancel() {
        terminationTask.cancel()
        if process.isRunning {
            process.terminate()
        }
    }

    func cleanup() throws {
        try isolatedSession.cleanup()
    }

    func deviceAuthPrompt() -> CodexDeviceAuthPrompt {
        prompt
    }
}

struct CodexLoginCaptureClient: CodexDeviceAuthCapturing {
    private let commandRunner: LocalCommandRunning
    private let codexExecutableURL: URL
    private let baseEnvironment: [String: String]

    init(
        commandRunner: LocalCommandRunning = LocalProcessCommandRunner(),
        codexExecutableURL: URL = URL(fileURLWithPath: "/usr/local/bin/codex"),
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.commandRunner = commandRunner
        self.codexExecutableURL = codexExecutableURL
        self.baseEnvironment = baseEnvironment
    }

    func beginDeviceAuth(in session: IsolatedCodexHomeSession) async throws -> any CodexDeviceAuthCaptureHandling {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let stdoutBuffer = LockedDataBuffer()
        let stderrBuffer = LockedDataBuffer()
        let promptState = LockedPromptState()

        process.executableURL = codexExecutableURL
        process.arguments = ["login", "--device-auth"]
        process.environment = executionEnvironment(for: session)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stdoutBuffer.append(chunk)
            promptState.store(
                prompt: Self.extractPrompt(from: String(decoding: stdoutBuffer.data, as: UTF8.self))
            )
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            stderrBuffer.append(chunk)
        }

        let terminationTask = Task<CommandResult, Error> {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil

                    let standardOutput = stdoutBuffer.data
                    stderrBuffer.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                    let standardError = stderrBuffer.data

                    continuation.resume(
                        returning: CommandResult(
                            terminationStatus: process.terminationStatus,
                            standardOutput: standardOutput,
                            standardError: standardError
                        )
                    )
                }

                do {
                    try process.run()
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }

        let prompt = try await waitForPrompt(
            from: promptState,
            process: process,
            terminationTask: terminationTask
        )

        return CodexDeviceAuthCaptureSession(
            prompt: prompt,
            process: process,
            isolatedSession: session,
            authFile: session.authFile,
            terminationTask: terminationTask
        )
    }

    func captureDeviceAuth(in session: IsolatedCodexHomeSession) async throws -> Data {
        if commandRunner is LocalProcessCommandRunner {
            let deviceAuthSession = try await beginDeviceAuth(in: session)
            return try await deviceAuthSession.waitForCapturedAuth()
        }

        let result = try await commandRunner.run(
            executableURL: codexExecutableURL,
            arguments: ["login", "--device-auth"],
            environment: executionEnvironment(for: session)
        )

        guard result.terminationStatus == 0 else {
            throw CodexLoginCaptureError.loginFailed(
                Self.commandFailureMessage(
                    standardError: result.standardError,
                    standardOutput: result.standardOutput,
                    terminationStatus: result.terminationStatus
                )
            )
        }

        guard FileManager.default.fileExists(atPath: session.authFile.path) else {
            throw CodexLoginCaptureError.missingCapturedAuth
        }

        return try Data(contentsOf: session.authFile)
    }

    private func executionEnvironment(for session: IsolatedCodexHomeSession) -> [String: String] {
        var environment = baseEnvironment
        environment["CODEX_HOME"] = session.rootDirectory.path
        return environment
    }

    private func waitForPrompt(
        from promptState: LockedPromptState,
        process: Process,
        terminationTask: Task<CommandResult, Error>
    ) async throws -> CodexDeviceAuthPrompt {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let prompt = promptState.currentPrompt {
                return prompt
            }

            if !process.isRunning {
                let result = try await terminationTask.value
                guard result.terminationStatus == 0 else {
                    throw CodexLoginCaptureError.loginFailed(
                        Self.commandFailureMessage(
                            standardError: result.standardError,
                            standardOutput: result.standardOutput,
                            terminationStatus: result.terminationStatus
                        )
                    )
                }
                break
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        if let prompt = promptState.currentPrompt {
            return prompt
        }

        if process.isRunning {
            process.terminate()
        }
        _ = try? await terminationTask.value
        throw CodexLoginCaptureError.missingDeviceAuthPrompt
    }

    private static func extractPrompt(from output: String) -> CodexDeviceAuthPrompt? {
        guard
            let urlMatch = output.range(of: #"https://auth\.openai\.com/codex/device\S*"#, options: .regularExpression),
            let verificationURL = URL(string: String(output[urlMatch]))
        else {
            return nil
        }

        let codeRange = output.range(
            of: #"\b[A-Z0-9]{4,}-[A-Z0-9]{4,}\b"#,
            options: .regularExpression
        )
        let userCode = codeRange.map { String(output[$0]) }

        return CodexDeviceAuthPrompt(
            verificationURL: verificationURL,
            userCode: userCode
        )
    }

    static func commandFailureMessage(
        standardError: Data,
        standardOutput: Data,
        terminationStatus: Int32
    ) -> String {
        let stderr = String(decoding: standardError, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }

        let stdout = String(decoding: standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty {
            return stdout
        }

        return "codex login --device-auth exited with status \(terminationStatus)."
    }
}

private final class LockedPromptState: @unchecked Sendable {
    private let lock = NSLock()
    private var prompt: CodexDeviceAuthPrompt?

    var currentPrompt: CodexDeviceAuthPrompt? {
        lock.lock()
        defer { lock.unlock() }
        return prompt
    }

    func store(prompt: CodexDeviceAuthPrompt?) {
        guard let prompt else { return }
        lock.lock()
        defer { lock.unlock() }
        self.prompt = prompt
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(chunk)
    }
}
