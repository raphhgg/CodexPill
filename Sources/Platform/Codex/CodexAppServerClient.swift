import Foundation
struct CodexAccountStatus {
    var email: String?
    var planType: String?
    var rateLimits: CodexRateLimitSnapshot?

    var remoteIdentity: CodexRemoteAccountIdentity? {
        CodexRemoteAccountIdentity(emailAddress: email)
    }
}

final class CodexAppServerClient {
    typealias StatusReader = @Sendable (_ refreshToken: Bool) async throws -> CodexAccountStatus
    typealias Sleeper = @Sendable (_ duration: Duration) async -> Void
    private let statusReader: StatusReader
    private let sleeper: Sleeper

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        statusReader = { refreshToken in
            try await Self.readAccountStatus(
                decoder: decoder,
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["codex", "app-server"],
                refreshToken: refreshToken
            )
        }
        sleeper = { duration in
            try? await Task.sleep(for: duration)
        }
    }

    init(
        statusReader: @escaping StatusReader,
        sleeper: @escaping Sleeper
    ) {
        self.statusReader = statusReader
        self.sleeper = sleeper
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        let attempts: [(refreshToken: Bool, delay: Duration)] = [
            (false, .zero),
            (true, .seconds(1))
        ]

        var latestPartialStatus: CodexAccountStatus?
        var latestError: Error?

        for (index, attempt) in attempts.enumerated() {
            if attempt.delay > .zero {
                await sleeper(attempt.delay)
            }

            do {
                let status = try await statusReader(attempt.refreshToken)
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

    private static func readAccountStatus(
        decoder: JSONDecoder,
        executableURL: URL,
        arguments: [String],
        refreshToken: Bool
    ) async throws -> CodexAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
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

            process.executableURL = executableURL
            process.arguments = arguments
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
                finish(.failure(appServerFailure(
                    stderr: state.capturedStderr(),
                    terminationStatus: Int(process.terminationStatus),
                    timedOut: false
                )))
            }

            do {
                try process.run()
                let requests = [
                    #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codexpill","title":"CodexPill","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}"#,
                    #"{"method":"initialized","params":{}}"#,
                    #"{"method":"account/read","id":2,"params":{"refreshToken":\#(refreshToken ? "true" : "false")}}"#,
                    #"{"method":"account/rateLimits/read","id":3,"params":{}}"#
                ]
                let payload = requests.joined(separator: "\n") + "\n"
                inputHandle.write(Data(payload.utf8))

                Task {
                    try? await Task.sleep(for: .seconds(4))
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
}

func consumeOutputData(
    _ data: Data,
    decoder: JSONDecoder,
    state: AppServerSessionState
) throws -> CodexAccountStatus? {
    for line in state.appendOutput(data) {
        guard let lineData = line.data(using: .utf8) else { continue }

        let envelope = try decoder.decode(AppServerEnvelope.self, from: lineData)
        switch envelope.id {
        case 2:
            let accountResponse = try decoder.decode(AppServerAccountResponse.self, from: envelope.result)
            state.setAccountResponse(accountResponse)
        case 3:
            let rateLimitResponse = try decoder.decode(AppServerRateLimitsResponse.self, from: envelope.result)
            state.setRateLimitResponse(rateLimitResponse)
        default:
            continue
        }

        if let snapshot = state.completeStatus() {
            return snapshot
        }
    }

    return nil
}

final class AppServerSessionState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var errorBuffer = Data()
    private var accountResponse: AppServerAccountResponse?
    private var rateLimitResponse: AppServerRateLimitsResponse?
    private var finished = false

    func appendOutput(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        return splitLines(from: &buffer)
    }

    func setAccountResponse(_ response: AppServerAccountResponse) {
        lock.lock()
        defer { lock.unlock() }
        accountResponse = response
    }

    func setRateLimitResponse(_ response: AppServerRateLimitsResponse) {
        lock.lock()
        defer { lock.unlock() }
        rateLimitResponse = response
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

    func completeStatus() -> CodexAccountStatus? {
        lock.lock()
        defer { lock.unlock() }
        guard accountResponse != nil, rateLimitResponse != nil else { return nil }
        return makeAccountStatus(account: accountResponse, rateLimits: rateLimitResponse)
    }

    func partialStatus() -> CodexAccountStatus? {
        lock.lock()
        defer { lock.unlock() }
        guard let accountResponse else { return nil }
        return makeAccountStatus(account: accountResponse, rateLimits: rateLimitResponse)
    }

    func markFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}

private func makeAccountStatus(
    account: AppServerAccountResponse?,
    rateLimits: AppServerRateLimitsResponse?
) -> CodexAccountStatus? {
    guard let account else { return nil }
    return CodexAccountStatus(
        email: account.account?.email,
        planType: account.account?.planType,
        rateLimits: rateLimits?.rateLimits.toModel()
    )
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
    let id: Int
    let result: Data

    private enum CodingKeys: String, CodingKey {
        case id
        case result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        let resultValue = try container.decode(JSONValue.self, forKey: .result)
        result = try JSONEncoder().encode(resultValue)
    }
}

struct AppServerAccountResponse: Decodable {
    let account: Account?

    struct Account: Decodable {
        let email: String?
        let planType: String?
    }
}

struct AppServerRateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot
}

struct RateLimitSnapshot: Decodable {
    let limitId: String?
    let limitName: String?
    let planType: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?

    func toModel() -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            limitID: limitId,
            limitName: limitName,
            planType: planType,
            primary: primary?.toModel(),
            secondary: secondary?.toModel(),
            fetchedAt: Date()
        )
    }
}

struct RateLimitWindow: Decodable {
    let usedPercent: Int
    let resetsAt: Int?
    let windowDurationMins: Int?

    func toModel() -> CodexRateLimitWindow {
        CodexRateLimitWindow(
            usedPercent: usedPercent,
            resetsAt: resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            windowDurationMinutes: windowDurationMins
        )
    }
}

func appServerFailure(
    stderr: String?,
    terminationStatus: Int?,
    timedOut: Bool
) -> CodexAppServerError {
    if let stderr, !stderr.isEmpty {
        return .server(stderr)
    }

    if let terminationStatus {
        return .terminated(terminationStatus)
    }

    if timedOut {
        return .timeout
    }

    return .timeout
}

enum CodexAppServerError: LocalizedError, Equatable {
    case server(String)
    case terminated(Int)
    case timeout
    case remoteConnectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .server(let message):
            "Codex app-server error: \(message)"
        case .terminated(let code):
            "Codex app-server exited with code \(code)."
        case .timeout:
            "Timed out while reading Codex account data."
        case .remoteConnectionFailed(let message):
            message
        }
    }
}

private enum JSONValue: Codable {
    case string(String)
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
