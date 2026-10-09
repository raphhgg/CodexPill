import Foundation

struct CommandResult: Equatable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
}

enum CommandRunnerError: Error, Equatable, LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            "Command timed out."
        }
    }
}

protocol CommandRunner: Sendable {
    func run(executableURL: URL, arguments: [String]) async throws -> CommandResult
}

struct ProcessCommandRunner: CommandRunner {
    var timeout: Duration = .seconds(30)
    var terminationGracePeriod: Duration = .milliseconds(200)

    func run(executableURL: URL, arguments: [String]) async throws -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let (exits, reportExit) = AsyncStream.makeStream(of: Int32.self)
        process.terminationHandler = { process in
            reportExit.yield(process.terminationStatus)
            reportExit.finish()
        }

        try Task.checkCancellation()
        try process.run()

        async let standardOutput = readToEnd(outputPipe)
        async let standardError = readToEnd(errorPipe)
        let timeoutWatchdog = Task {
            try await Task.sleep(for: timeout)
            return stop(process)
        }

        // The exit wait runs in its own task so cancelling the caller stops the process instead of abandoning it.
        let terminationStatus = await withTaskCancellationHandler {
            await Task { await exits.first { _ in true } ?? process.terminationStatus }.value
        } onCancel: {
            stop(process)
        }
        timeoutWatchdog.cancel()

        let result = await CommandResult(
            terminationStatus: terminationStatus,
            standardOutput: standardOutput,
            standardError: standardError
        )
        try Task.checkCancellation()
        if (try? await timeoutWatchdog.value) == true {
            throw CommandRunnerError.timedOut
        }
        return result
    }

    @discardableResult
    private func stop(_ process: Process) -> Bool {
        guard process.isRunning else { return false }
        process.terminate()
        Task {
            try? await Task.sleep(for: terminationGracePeriod)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        return true
    }

    private func readToEnd(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile())
            }
        }
    }
}
