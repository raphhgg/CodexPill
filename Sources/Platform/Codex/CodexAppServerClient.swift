import Foundation
struct CodexAccountStatus: Equatable {
    var email: String?
    var planType: String?
    var rateLimits: CodexRateLimitSnapshot?
    var stableAccountID: String? = nil
    var authPrincipalIdentity: CodexAuthPrincipalIdentity? = nil
    var workspaceIdentity: CodexWorkspaceIdentity? = nil
    var snapshotFingerprint: String? = nil

    var remoteIdentity: CodexRemoteAccountIdentity? {
        CodexRemoteAccountIdentity(emailAddress: email)
    }
}

protocol CodexAccountStatusClient {
    func readCurrentAccountStatus() async throws -> CodexAccountStatus
}

extension CodexAppServerClient: CodexAccountStatusClient {}

protocol SavedCodexAccountStatusClient {
    func readSavedAccountStatus(authData: Data) async throws -> CodexAccountStatus
}

extension CodexAppServerClient: SavedCodexAccountStatusClient {}

struct CodexCLICommand: Equatable {
    let executableURL: URL
    let arguments: [String]
}

final class CodexAppServerClient {
    typealias StatusSource = @Sendable (_ refreshToken: Bool) async throws -> CodexAccountStatus
    typealias Sleeper = @Sendable (_ duration: Duration) async -> Void
    private static let responseTimeout: Duration = .seconds(10)
    private let statusSource: StatusSource
    private let sleeper: Sleeper
    private let command: CodexCLICommand

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let command = Self.makeAppServerCommand(environment: environment)
        self.command = command
        statusSource = { refreshToken in
            try await Self.readAccountStatus(
                decoder: decoder,
                executableURL: command.executableURL,
                arguments: command.arguments,
                environment: environment,
                refreshToken: refreshToken,
                requireRateLimitResponse: false
            )
        }
        sleeper = { duration in
            try? await Task.sleep(for: duration)
        }
    }

    init(
        statusSource: @escaping StatusSource,
        sleeper: @escaping Sleeper
    ) {
        command = CodexCLICommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["codex", "app-server"]
        )
        self.statusSource = statusSource
        self.sleeper = sleeper
    }

    func readCurrentAccountStatus() async throws -> CodexAccountStatus {
        let attempts: [(refreshToken: Bool, delay: Duration)] = [
            (false, .zero),
            (true, .seconds(1)),
            (true, .seconds(3))
        ]

        var latestPartialStatus: CodexAccountStatus?
        var latestError: Error?

        for (index, attempt) in attempts.enumerated() {
            if attempt.delay > .zero {
                await sleeper(attempt.delay)
            }

            do {
                let status = try await statusSource(attempt.refreshToken)
                latestPartialStatus = mergeStatuses(previous: latestPartialStatus, current: status)

                guard shouldRetry(status: latestPartialStatus, attemptIndex: index, totalAttempts: attempts.count) else {
                    return latestPartialStatus ?? status
                }
            } catch {
                latestError = error

                if let latestPartialStatus {
                    return latestPartialStatus
                }

                guard index < attempts.count - 1 else {
                    throw error
                }

                guard shouldRetry(error: error, attemptIndex: index, totalAttempts: attempts.count) else {
                    throw error
                }
            }
        }

        if let latestPartialStatus {
            return latestPartialStatus
        }

        throw latestError ?? CocoaError(.coderReadCorrupt)
    }

    func readSavedAccountStatus(authData: Data) async throws -> CodexAccountStatus {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try IsolatedCodexHomeSession.create()
        defer { try? session.cleanup() }

        try authData.write(to: session.authFile, options: .atomic)

        return try await Self.readAccountStatus(
            decoder: decoder,
            executableURL: command.executableURL,
            arguments: command.arguments,
            environment: Self.isolatedAppServerEnvironment(command: command, session: session),
            refreshToken: true,
            requireRateLimitResponse: true
        )
    }

    private func shouldRetry(status: CodexAccountStatus?, attemptIndex: Int, totalAttempts: Int) -> Bool {
        guard attemptIndex < totalAttempts - 1 else { return false }
        guard attemptIndex == 0 else { return false }
        return appServerStatusNeedsRetry(status)
    }

    private func shouldRetry(error: Error, attemptIndex: Int, totalAttempts: Int) -> Bool {
        guard attemptIndex < totalAttempts - 1 else { return false }
        guard attemptIndex > 0 else { return true }
        return isRateLimitReadFailure(error)
    }

    private func isRateLimitReadFailure(_ error: Error) -> Bool {
        guard case .server(let message) = error as? CodexAppServerError else {
            return false
        }
        let normalizedMessage = message.lowercased()
        return normalizedMessage.contains("rate limit") || normalizedMessage.contains("ratelimit")
    }

    private func mergeStatuses(previous: CodexAccountStatus?, current: CodexAccountStatus) -> CodexAccountStatus {
        mergeAppServerStatuses(previous: previous, current: current)
    }

    static func makeAppServerCommand(environment: [String: String]) -> CodexCLICommand {
        if let overridePath = environment["CODEX_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            return CodexCLICommand(
                executableURL: URL(fileURLWithPath: overridePath),
                arguments: ["app-server"]
            )
        }

        let bundlePath = Bundle.main.sharedSupportPath.map {
            URL(fileURLWithPath: $0)
                .appendingPathComponent("codex")
                .standardizedFileURL.path
        }
        let fallbackPaths = [
            bundlePath,
            "/Applications/Codex.app/Contents/Resources/codex"
        ].compactMap { $0 }

        let fileManager = FileManager.default
        if let resolvedPath = fallbackPaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return CodexCLICommand(
                executableURL: URL(fileURLWithPath: resolvedPath),
                arguments: ["app-server"]
            )
        }

        return CodexCLICommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["codex", "app-server"]
        )
    }

    static func makeAppServerRequests(refreshToken: Bool) -> [String] {
        [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codexpill","title":"CodexPill","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}"#,
            #"{"method":"initialized","params":{}}"#,
            #"{"method":"account/read","id":2,"params":{"refreshToken":\#(refreshToken ? "true" : "false")}}"#,
            #"{"method":"account/rateLimits/read","id":3,"params":null}"#
        ]
    }

    private static func readAccountStatus(
        decoder: JSONDecoder,
        executableURL: URL,
        arguments: [String],
        environment: [String: String]?,
        refreshToken: Bool,
        requireRateLimitResponse: Bool
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
            process.environment = environment
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
                let requests = makeAppServerRequests(refreshToken: refreshToken)
                let payload = requests.joined(separator: "\n") + "\n"
                inputHandle.write(Data(payload.utf8))

                Task {
                    try? await Task.sleep(for: responseTimeout)
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

    private static func isolatedAppServerEnvironment(
        command: CodexCLICommand,
        session: IsolatedCodexHomeSession,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        let executableDirectory = command.executableURL.deletingLastPathComponent().path
        environment["CODEX_HOME"] = session.rootDirectory.path
        environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        environment["LOGNAME"] = NSUserName()
        environment["PATH"] = "\(executableDirectory):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["TMPDIR"] = session.tempDirectory.path
        environment["USER"] = NSUserName()
        return environment
    }
}

func appServerStatusNeedsRetry(_ status: CodexAccountStatus?) -> Bool {
    guard let status else { return true }
    guard status.email != nil else { return true }
    return !appServerRateLimitsAreComplete(status.rateLimits)
}

func appServerRateLimitsAreComplete(_ snapshot: CodexRateLimitSnapshot?) -> Bool {
    guard let snapshot else { return false }
    return snapshot.primary != nil && snapshot.secondary != nil
}

func appServerRateLimitsLookSuspiciouslyZeroed(_ snapshot: CodexRateLimitSnapshot?) -> Bool {
    guard let snapshot else { return false }
    return appServerRateLimitWindowLooksSuspiciouslyZeroed(snapshot.primary)
        && appServerRateLimitWindowLooksSuspiciouslyZeroed(snapshot.secondary)
}

func appServerRateLimitWindowLooksSuspiciouslyZeroed(_ window: CodexRateLimitWindow?) -> Bool {
    guard let window, window.usedPercent == 0, let resetsAt = window.resetsAt else { return false }
    return resetsAt > .now
}

func mergeAppServerStatuses(previous: CodexAccountStatus?, current: CodexAccountStatus) -> CodexAccountStatus {
    CodexAccountStatus(
        email: current.email ?? previous?.email,
        planType: current.planType ?? previous?.planType,
        rateLimits: mergeAppServerRateLimits(previous: previous?.rateLimits, current: current.rateLimits),
        stableAccountID: current.stableAccountID ?? previous?.stableAccountID,
        authPrincipalIdentity: current.authPrincipalIdentity ?? previous?.authPrincipalIdentity,
        workspaceIdentity: current.workspaceIdentity ?? previous?.workspaceIdentity,
        snapshotFingerprint: current.snapshotFingerprint ?? previous?.snapshotFingerprint
    )
}

func mergeAppServerRateLimits(
    previous: CodexRateLimitSnapshot?,
    current: CodexRateLimitSnapshot?
) -> CodexRateLimitSnapshot? {
    guard previous != nil || current != nil else { return nil }
    guard let current else { return previous }
    guard let previous else { return current }

    return CodexRateLimitSnapshot(
        limitID: current.limitID ?? previous.limitID,
        limitName: current.limitName ?? previous.limitName,
        planType: current.planType ?? previous.planType,
        primary: mergeAppServerRateLimitWindow(previous: previous.primary, current: current.primary),
        secondary: mergeAppServerRateLimitWindow(previous: previous.secondary, current: current.secondary),
        fetchedAt: max(previous.fetchedAt, current.fetchedAt)
    )
}

func mergeAppServerRateLimitWindow(
    previous: CodexRateLimitWindow?,
    current: CodexRateLimitWindow?
) -> CodexRateLimitWindow? {
    guard previous != nil || current != nil else { return nil }
    guard let current else { return previous }
    guard let previous else { return current }

    return CodexRateLimitWindow(
        usedPercent: current.usedPercent,
        resetsAt: current.resetsAt ?? previous.resetsAt,
        windowDurationMinutes: current.windowDurationMinutes ?? previous.windowDurationMinutes
    )
}

func consumeOutputData(
    _ data: Data,
    decoder: JSONDecoder,
    state: AppServerSessionState
) throws -> CodexAccountStatus? {
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
                let accountResponse = try decoder.decode(AppServerAccountResponse.self, from: result)
                state.setAccountResponse(accountResponse)
            case 3:
                let rateLimitResponse = try decoder.decode(AppServerRateLimitsResponse.self, from: result)
                state.setRateLimitResponse(rateLimitResponse)
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

    func hasRateLimitResponse() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return rateLimitResponse != nil
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
        rateLimits: rateLimits?.preferredRateLimits(),
        stableAccountID: account.account?.stableAccountID,
        authPrincipalIdentity: account.account?.authPrincipalIdentity,
        workspaceIdentity: account.account?.workspaceIdentity,
        snapshotFingerprint: account.account?.snapshotFingerprint
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

struct AppServerAccountResponse: Decodable {
    let account: Account?

    struct Account: Decodable {
        let email: String?
        let planType: String?
        let stableAccountID: String?
        let authPrincipalIdentity: CodexAuthPrincipalIdentity?
        let workspaceIdentity: CodexWorkspaceIdentity?
        let snapshotFingerprint: String?
    }
}

struct AppServerRateLimitsResponse: Decodable {
    let rateLimits: RateLimitSnapshot?
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?

    init(
        rateLimits: RateLimitSnapshot?,
        rateLimitsByLimitId: [String: RateLimitSnapshot]? = nil
    ) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
    }

    func preferredRateLimits() -> CodexRateLimitSnapshot? {
        if let codex = rateLimitsByLimitId?["codex"]?.toModel(),
           appServerRateLimitsAreComplete(codex) {
            return codex
        }
        return rateLimits?.toModel()
    }
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
    let usedPercent: Int?
    let resetsAt: Int?
    let windowDurationMins: Int?

    func toModel() -> CodexRateLimitWindow? {
        guard let usedPercent else { return nil }
        return CodexRateLimitWindow(
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

private func friendlyAppServerDecodingMessage(for error: DecodingError) -> String {
    switch error {
    case .keyNotFound:
        return "Codex returned an incomplete app-server response."
    case .valueNotFound:
        return "Codex returned an incomplete app-server response."
    case .typeMismatch:
        return "Codex returned an invalid app-server response."
    case .dataCorrupted:
        return "Codex returned an unreadable app-server response."
    @unknown default:
        return "Codex returned an invalid app-server response."
    }
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
