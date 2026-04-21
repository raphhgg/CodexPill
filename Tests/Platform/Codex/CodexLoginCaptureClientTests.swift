import Foundation
import Testing

@testable import CodexPill

struct CodexLoginCaptureClientTests {
    @Test
    func captureDeviceAuthRunsLoginUnderIsolatedCodexHomeAndReadsCapturedAuthFile() async throws {
        let session = try IsolatedCodexHomeSession.create()
        defer { try? session.cleanup() }

        let expectedAuth = Data(#"{"tokens":{"account_id":"acct-123"}}"#.utf8)
        let runner = LocalCommandRunnerSpy { call in
            try expectedAuth.write(to: session.authFile, options: .atomic)
            #expect(call.executableURL.path == "/usr/local/bin/codex")
            #expect(call.arguments == ["login", "--device-auth"])
            #expect(call.environment["CODEX_HOME"] == session.rootDirectory.path)
            return CommandResult(
                terminationStatus: 0,
                standardOutput: Data(),
                standardError: Data()
            )
        }
        let client = CodexLoginCaptureClient(
            commandRunner: runner,
            codexExecutableURL: URL(fileURLWithPath: "/usr/local/bin/codex")
        )

        let capturedAuth = try await client.captureDeviceAuth(in: session)

        #expect(capturedAuth == expectedAuth)
        #expect(runner.calls.count == 1)
    }

    @Test
    func captureDeviceAuthFailsWhenLoginCommandExitsNonZero() async {
        let session = try! IsolatedCodexHomeSession.create()
        defer { try? session.cleanup() }

        let runner = LocalCommandRunnerSpy { _ in
            CommandResult(
                terminationStatus: 1,
                standardOutput: Data(),
                standardError: Data("login failed".utf8)
            )
        }
        let client = CodexLoginCaptureClient(
            commandRunner: runner,
            codexExecutableURL: URL(fileURLWithPath: "/usr/local/bin/codex")
        )

        await #expect(throws: CodexLoginCaptureError.loginFailed("login failed")) {
            _ = try await client.captureDeviceAuth(in: session)
        }
    }

    @Test
    func captureDeviceAuthFailsWhenAuthFileWasNotProduced() async {
        let session = try! IsolatedCodexHomeSession.create()
        defer { try? session.cleanup() }

        let runner = LocalCommandRunnerSpy { _ in
            CommandResult(
                terminationStatus: 0,
                standardOutput: Data(),
                standardError: Data()
            )
        }
        let client = CodexLoginCaptureClient(
            commandRunner: runner,
            codexExecutableURL: URL(fileURLWithPath: "/usr/local/bin/codex")
        )

        await #expect(throws: CodexLoginCaptureError.missingCapturedAuth) {
            _ = try await client.captureDeviceAuth(in: session)
        }
    }
}

private final class LocalCommandRunnerSpy: LocalCommandRunning {
    struct Call {
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
    }

    private let handler: (Call) throws -> CommandResult
    private(set) var calls: [Call] = []

    init(handler: @escaping (Call) throws -> CommandResult) {
        self.handler = handler
    }

    func run(executableURL: URL, arguments: [String], environment: [String: String]) async throws -> CommandResult {
        let call = Call(executableURL: executableURL, arguments: arguments, environment: environment)
        calls.append(call)
        return try handler(call)
    }
}
