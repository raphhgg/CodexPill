import Foundation

struct CommandResult: Equatable {
    let terminationStatus: Int32
    let standardOutput: Data
    let standardError: Data
}

protocol CommandRunner: Sendable {
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
