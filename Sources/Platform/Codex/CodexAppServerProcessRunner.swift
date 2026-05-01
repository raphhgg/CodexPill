import Foundation

struct CodexAppServerProcessRunner {
    func readAccountStatus(
        configuration: CodexAppServerConfiguration,
        refreshToken: Bool,
        requireRateLimitResponse: Bool
    ) async throws -> CodexAppServerStatus {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let inputPipe = Pipe()
            let inputHandle = inputPipe.fileHandleForWriting
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = CodexAppServerSessionState()

            let finish: @Sendable (Result<CodexAppServerStatus, Error>) -> Void = { result in
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
                    if let snapshot = try CodexAppServerSession.consumeOutputData(data, decoder: decoder, state: state) {
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

            process.executableURL = configuration.command.executableURL
            process.arguments = configuration.command.arguments
            process.environment = configuration.environment
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { process in
                let trailingOutput = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if !trailingOutput.isEmpty {
                    do {
                        if let snapshot = try CodexAppServerSession.consumeOutputData(
                            trailingOutput,
                            decoder: decoder,
                            state: state
                        ) {
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

                if process.terminationStatus == 0,
                   !requireRateLimitResponse,
                   let partialStatus = state.partialStatus() {
                    finish(.success(partialStatus))
                    return
                }

                if process.terminationStatus == 0, requireRateLimitResponse, !state.hasRateLimitResponse() {
                    finish(.failure(CodexAppServerError.server("Codex app-server ended before returning rate limits.")))
                    return
                }

                guard process.terminationStatus != 0 else { return }
                finish(.failure(appServerFailure(
                    stderr: state.capturedStderr(),
                    terminationStatus: Int(process.terminationStatus),
                    timedOut: false
                )))
            }

            do {
                try process.run()
                let requests = CodexAppServerSession.makeRequests(
                    refreshToken: refreshToken,
                    clientInfo: configuration.clientInfo
                )
                let payload = requests.joined(separator: "\n") + "\n"
                inputHandle.write(Data(payload.utf8))

                Task {
                    try? await Task.sleep(for: configuration.responseTimeout)
                    if !requireRateLimitResponse, let partialStatus = state.partialStatus() {
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
}
