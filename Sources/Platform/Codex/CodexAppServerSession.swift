import Foundation

final class CodexAppServerSessionState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var errorBuffer = Data()
    private var account: CodexAppServerAccount?
    private var rateLimits: CodexAppServerRateLimits?
    private var receivedRateLimitResponse = false
    private var finished = false

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

    func markFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }
}

typealias AppServerSessionState = CodexAppServerSessionState

struct CodexAppServerSession {
    static func makeRequests(
        refreshToken: Bool,
        clientInfo: CodexAppServerClientInfo = .codexPill
    ) -> [String] {
        [
            initializeRequest(clientInfo: clientInfo),
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/read","id":2,"params":{"refreshToken":\#(refreshToken ? "true" : "false")}}"#,
            #"{"method":"account/rateLimits/read","id":3,"params":null}"#
        ]
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
        .map(CodexPillAccountStatusMapper().status)
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
