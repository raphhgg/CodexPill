import Foundation

final class CodexAppServerSessionState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var errorBuffer = Data()
    private var account: CodexAppServerAccount?
    private var rateLimits: CodexAppServerRateLimits?
    private var receivedRateLimitResponse = false
    private var finished = false
    private var outputClosed = false
    private var terminationStatus: Int32?

    func appendOutput(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        return splitLines(from: &buffer)
    }

    func setAccount(_ account: CodexAppServerAccount?) {
        lock.lock()
        defer { lock.unlock() }
        self.account = account
    }

    func setAccountResponse(_ response: AppServerAccountResponse) {
        setAccount(CodexAppServerAccountParser().parse(response))
    }

    func setRateLimits(_ rateLimits: CodexAppServerRateLimits?) {
        lock.lock()
        defer { lock.unlock() }
        self.rateLimits = rateLimits
        receivedRateLimitResponse = true
    }

    func setRateLimitResponse(_ response: AppServerRateLimitsResponse) {
        setRateLimits(CodexAppServerRateLimitParser().parse(response))
    }

    func appendErrorOutput(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        errorBuffer.append(data)
    }

    func capturedStderr() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let stderr = String(decoding: errorBuffer, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stderr.isEmpty ? nil : stderr
    }

    func completeStatus() -> CodexAppServerStatus? {
        lock.lock()
        defer { lock.unlock() }
        guard let account, receivedRateLimitResponse else { return nil }
        return CodexAppServerStatus(account: account, rateLimits: rateLimits)
    }

    func partialStatus() -> CodexAppServerStatus? {
        lock.lock()
        defer { lock.unlock() }
        guard let account else { return nil }
        return CodexAppServerStatus(account: account, rateLimits: rateLimits)
    }

    func hasRateLimitResponse() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return receivedRateLimitResponse
    }

    /// Returns the exit status once Codex has also exited, so the caller decides only after both.
    func closeOutput() -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        outputClosed = true
        return terminationStatus
    }

    /// Returns true once Codex's output has also closed, so the caller decides only after both.
    func recordTermination(status: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        terminationStatus = status
        return outputClosed
    }

    func markFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}

typealias AppServerSessionState = CodexAppServerSessionState

struct CodexAppServerSessionCommand {
    let executableURL: URL?
    let arguments: [String]
    let environment: [String: String]?
    let timeout: Duration
    let refreshToken: Bool
    let clientInfo: CodexAppServerClientInfo
    let requireRateLimitResponse: Bool
    let prematureRateLimitExitMessage: String
    let failure: @Sendable (_ stderr: String?, _ terminationStatus: Int?, _ timedOut: Bool) -> Error

    init(
        executableURL: URL?,
        arguments: [String],
        environment: [String: String]? = nil,
        timeout: Duration,
        refreshToken: Bool,
        clientInfo: CodexAppServerClientInfo = .refill,
        requireRateLimitResponse: Bool,
        prematureRateLimitExitMessage: String = "Codex app-server ended before returning rate limits.",
        failure: @escaping @Sendable (_ stderr: String?, _ terminationStatus: Int?, _ timedOut: Bool) -> Error
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.timeout = timeout
        self.refreshToken = refreshToken
        self.clientInfo = clientInfo
        self.requireRateLimitResponse = requireRateLimitResponse
        self.prematureRateLimitExitMessage = prematureRateLimitExitMessage
        self.failure = failure
    }
}

struct CodexAppServerSessionRunner {
    func readAccountStatus(command: CodexAppServerSessionCommand) async throws -> CodexAppServerStatus {
        let state = CodexAppServerSessionState()
        return try await run(
            executableURL: command.executableURL,
            arguments: command.arguments,
            environment: command.environment,
            timeout: command.timeout,
            requests: CodexAppServerSession.makeRequests(
                refreshToken: command.refreshToken,
                clientInfo: command.clientInfo
            ),
            state: state,
            consume: { data, decoder in
                try CodexAppServerSession.consumeOutputData(data, decoder: decoder, state: state)
            },
            cleanExit: {
                if !command.requireRateLimitResponse, let partialStatus = state.partialStatus() {
                    return .success(partialStatus)
                }
                if command.requireRateLimitResponse, !state.hasRateLimitResponse() {
                    return .failure(CodexAppServerError.server(command.prematureRateLimitExitMessage))
                }
                return nil
            },
            timeoutFallback: {
                command.requireRateLimitResponse ? nil : state.partialStatus()
            },
            failure: command.failure
        )
    }

    func consumeResetCredit(command: CodexResetCreditConsumeCommand) async throws -> CodexResetCreditOutcome {
        let state = CodexAppServerSessionState()
        return try await run(
            executableURL: command.executableURL,
            arguments: command.arguments,
            environment: command.environment,
            timeout: command.timeout,
            requests: CodexAppServerSession.makeResetCreditConsumeRequests(
                idempotencyKey: command.idempotencyKey,
                clientInfo: command.clientInfo
            ),
            state: state,
            consume: { data, decoder in
                try CodexAppServerSession.consumeResetCreditOutput(data, decoder: decoder, state: state)
            },
            cleanExit: {
                .failure(CodexAppServerError.server("Codex app-server ended before using the reset."))
            },
            timeoutFallback: { nil },
            failure: command.failure
        )
    }

    /// Starts `codex app-server`, writes the requests, and finishes with the first response that
    /// `consume` returns, a clean-exit or timeout fallback, or `failure`.
    private func run<Response: Sendable>(
        executableURL: URL?,
        arguments: [String],
        environment: [String: String]?,
        timeout: Duration,
        requests: [String],
        state: CodexAppServerSessionState,
        consume: @escaping @Sendable (Data, JSONDecoder) throws -> Response?,
        cleanExit: @escaping @Sendable () -> Result<Response, Error>?,
        timeoutFallback: @escaping @Sendable () -> Response?,
        failure: @escaping @Sendable (_ stderr: String?, _ terminationStatus: Int?, _ timedOut: Bool) -> Error
    ) async throws -> Response {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let inputPipe = Pipe()
            let inputHandle = inputPipe.fileHandleForWriting
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let finish: @Sendable (Result<Response, Error>) -> Void = { result in
                guard state.markFinished() else { return }
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                try? inputHandle.close()
                if process.isRunning {
                    process.terminate()
                }
                continuation.resume(with: result)
            }

            let settle: @Sendable (Int32) -> Void = { terminationStatus in
                if terminationStatus == 0 {
                    if let result = cleanExit() {
                        finish(result)
                    }
                    return
                }

                finish(.failure(failure(
                    state.capturedStderr(),
                    Int(terminationStatus),
                    false
                )))
            }

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    if let terminationStatus = state.closeOutput() {
                        settle(terminationStatus)
                    }
                    return
                }

                do {
                    if let response = try consume(data, decoder) {
                        finish(.success(response))
                    }
                } catch {
                    finish(.failure(error))
                }
            }

            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = environment
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { process in
                let trailingError = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if !trailingError.isEmpty {
                    state.appendErrorOutput(trailingError)
                }

                if state.recordTermination(status: process.terminationStatus) {
                    settle(process.terminationStatus)
                }
            }

            do {
                try process.run()
                let payload = requests.joined(separator: "\n") + "\n"
                inputHandle.write(Data(payload.utf8))

                Task {
                    try? await Task.sleep(for: timeout)
                    if let response = timeoutFallback() {
                        finish(.success(response))
                        return
                    }
                    finish(.failure(failure(
                        state.capturedStderr(),
                        nil,
                        true
                    )))
                }
            } catch {
                finish(.failure(error))
            }
        }
    }
}

struct CodexAppServerSession {
    static func makeRequests(
        refreshToken: Bool,
        clientInfo: CodexAppServerClientInfo = .refill
    ) -> [String] {
        [
            initializeRequest(clientInfo: clientInfo),
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/read","id":2,"params":{"refreshToken":\#(refreshToken ? "true" : "false")}}"#,
            #"{"method":"account/rateLimits/read","id":3,"params":null}"#
        ]
    }

    static func makeResetCreditConsumeRequests(
        idempotencyKey: UUID,
        clientInfo: CodexAppServerClientInfo = .refill
    ) -> [String] {
        [
            initializeRequest(clientInfo: clientInfo),
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/rateLimitResetCredit/consume","id":2,"params":{"idempotencyKey":"\#(idempotencyKey.uuidString)"}}"#
        ]
    }

    static func consumeResetCreditOutput(
        _ data: Data,
        decoder: JSONDecoder,
        state: CodexAppServerSessionState
    ) throws -> CodexResetCreditOutcome? {
        for line in state.appendOutput(data) {
            guard let lineData = line.data(using: .utf8) else { continue }

            do {
                let envelope = try decoder.decode(AppServerEnvelope.self, from: lineData)
                guard envelope.id == 2 else { continue }

                if let error = envelope.error {
                    throw CodexAppServerError.server(error.message)
                }
                guard let result = envelope.result else {
                    throw CodexAppServerError.server("Codex returned an incomplete app-server response.")
                }
                let response = try decoder.decode(AppServerResetCreditConsumeResponse.self, from: result)
                return CodexResetCreditOutcome(rawValue: response.outcome) ?? .unrecognized
            } catch let error as DecodingError {
                throw CodexAppServerError.server(friendlyAppServerDecodingMessage(for: error))
            }
        }

        return nil
    }

    private static func initializeRequest(clientInfo: CodexAppServerClientInfo) -> String {
        let payload: [String: Any] = [
            "method": "initialize",
            "id": 1,
            "params": [
                "clientInfo": [
                    "name": clientInfo.name,
                    "title": clientInfo.title,
                    "version": clientInfo.version
                ],
                "capabilities": [
                    "experimentalApi": true
                ]
            ]
        ]
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? #"{"method":"initialize","id":1}"#
    }

    static func consumeOutputData(
        _ data: Data,
        decoder: JSONDecoder,
        state: CodexAppServerSessionState
    ) throws -> CodexAppServerStatus? {
        let accountParser = CodexAppServerAccountParser()
        let rateLimitParser = CodexAppServerRateLimitParser()

        for line in state.appendOutput(data) {
            guard let lineData = line.data(using: .utf8) else { continue }

            do {
                let envelope = try decoder.decode(AppServerEnvelope.self, from: lineData)
                guard let id = envelope.id else {
                    continue
                }

                if let error = envelope.error {
                    throw CodexAppServerError.server(error.message)
                }

                guard let result = envelope.result else {
                    throw CodexAppServerError.server("Codex returned an incomplete app-server response.")
                }

                switch id {
                case 2:
                    let response = try decoder.decode(AppServerAccountResponse.self, from: result)
                    state.setAccount(accountParser.parse(response))
                case 3:
                    let response = try decoder.decode(AppServerRateLimitsResponse.self, from: result)
                    state.setRateLimits(rateLimitParser.parse(response))
                default:
                    continue
                }
            } catch let error as DecodingError {
                throw CodexAppServerError.server(friendlyAppServerDecodingMessage(for: error))
            }

            if let snapshot = state.completeStatus() {
                return snapshot
            }
        }

        return nil
    }
}

func consumeOutputData(
    _ data: Data,
    decoder: JSONDecoder,
    state: AppServerSessionState
) throws -> CodexAccountStatus? {
    try CodexAppServerSession.consumeOutputData(data, decoder: decoder, state: state)
        .map(RefillAccountStatusMapper().status)
}

private func splitLines(from buffer: inout Data) -> [String] {
    let newline = Data([0x0A])
    var lines: [String] = []

    while let range = buffer.range(of: newline) {
        let lineData = buffer.subdata(in: 0..<range.lowerBound)
        buffer.removeSubrange(0..<range.upperBound)
        if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
            lines.append(line)
        }
    }

    return lines
}

struct AppServerEnvelope: Decodable {
    let id: Int?
    let result: Data?
    let error: AppServerErrorResponse?

    private enum CodingKeys: String, CodingKey {
        case id
        case result
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        error = try container.decodeIfPresent(AppServerErrorResponse.self, forKey: .error)

        if let resultValue = try container.decodeIfPresent(JSONValue.self, forKey: .result) {
            result = try JSONEncoder().encode(resultValue)
        } else {
            result = nil
        }
    }
}

struct AppServerErrorResponse: Decodable, Equatable {
    let code: Int
    let message: String
}

private enum JSONValue: Codable {
    case string(String)
    case integer(Int)
    case number(Double)
    case object([String: JSONValue])
    case array([JSONValue])
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
