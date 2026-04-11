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
    private let decoder = JSONDecoder()

    init() {
        decoder.dateDecodingStrategy = .iso8601
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        try await readAccountStatus(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["codex", "app-server"]
        )
    }

    private func readAccountStatus(executableURL: URL, arguments: [String]) async throws -> CodexAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let state = AppServerSessionState()

            let finish: @Sendable (Result<CodexAccountStatus, Error>) -> Void = { result in
                guard state.markFinished() else { return }
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                if process.isRunning {
                    process.terminate()
                }
                continuation.resume(with: result)
            }

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                for line in state.appendOutput(data) {
                    guard let lineData = line.data(using: .utf8) else { continue }
                    do {
                        let envelope = try self.decoder.decode(AppServerEnvelope.self, from: lineData)
                        switch envelope.id {
                        case 2:
                            let accountResponse = try self.decoder.decode(AppServerAccountResponse.self, from: envelope.result)
                            state.setAccountResponse(accountResponse)
                        case 3:
                            let rateLimitResponse = try self.decoder.decode(AppServerRateLimitsResponse.self, from: envelope.result)
                            state.setRateLimitResponse(rateLimitResponse)
                        default:
                            continue
                        }

                        if let snapshot = state.snapshot() {
                            finish(.success(CodexAccountStatus(
                                email: snapshot.account.account?.email,
                                planType: snapshot.account.account?.planType,
                                rateLimits: snapshot.rateLimits.rateLimits.toModel()
                            )))
                            return
                        }
                    } catch {
                        finish(.failure(error))
                        return
                    }
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let stderr = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !stderr.isEmpty else { return }
                finish(.failure(CodexAppServerError.server(stderr)))
            }

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { process in
                guard process.terminationStatus != 0 else { return }
                finish(.failure(CodexAppServerError.terminated(Int(process.terminationStatus))))
            }

            do {
                try process.run()
                let requests = [
                    #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codexpill","title":"CodexPill","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}"#,
                    #"{"method":"account/read","id":2,"params":{"refreshToken":false}}"#,
                    #"{"method":"account/rateLimits/read","id":3,"params":null}"#
                ]
                let payload = requests.joined(separator: "\n") + "\n"
                inputPipe.fileHandleForWriting.write(Data(payload.utf8))

                Task {
                    try? await Task.sleep(for: .seconds(4))
                    finish(.failure(CodexAppServerError.timeout))
                }
            } catch {
                finish(.failure(error))
            }
        }
    }
}

private final class AppServerSessionState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
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

    func snapshot() -> (account: AppServerAccountResponse, rateLimits: AppServerRateLimitsResponse)? {
        lock.lock()
        defer { lock.unlock() }
        guard let accountResponse, let rateLimitResponse else { return nil }
        return (accountResponse, rateLimitResponse)
    }

    func markFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
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

private struct AppServerEnvelope: Decodable {
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

private struct AppServerAccountResponse: Decodable {
    let account: Account?

    struct Account: Decodable {
        let email: String?
        let planType: String?
    }
}

private struct AppServerRateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot
}

private struct RateLimitSnapshot: Decodable {
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

private struct RateLimitWindow: Decodable {
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

private enum CodexAppServerError: LocalizedError {
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
