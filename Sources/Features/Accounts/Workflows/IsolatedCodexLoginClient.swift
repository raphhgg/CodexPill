import AppKit
import Foundation

struct IsolatedCodexLoginPrompt: Equatable {
    let url: URL
    let userCode: String
}

protocol IsolatedCodexLoginSession: AnyObject {
    var prompt: IsolatedCodexLoginPrompt { get }
    var codexHome: URL { get }
    func waitForAuthData() async throws -> Data
    func verifyLoginStatus() async -> Bool
    func cancel()
    func cleanup()
}

protocol IsolatedCodexLoginClient {
    func startLogin() async throws -> IsolatedCodexLoginSession
}

struct SystemIsolatedCodexLoginClient: IsolatedCodexLoginClient {
    func startLogin() async throws -> IsolatedCodexLoginSession {
        let codexURL = try resolveCodexExecutable()
        let session = try IsolatedCodexHomeSession.create()
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let output = LockedStringBuffer()

        process.executableURL = codexURL
        process.arguments = ["login", "--device-auth"]
        process.environment = executionEnvironment(codexURL: codexURL, isolatedSession: session)
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            output.append(String(decoding: data, as: UTF8.self))
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        try process.run()
        do {
            let prompt = try await waitForPrompt(output: output, process: process)
            return RunningIsolatedCodexLoginSession(
                prompt: prompt,
                codexURL: codexURL,
                isolatedSession: session,
                process: process
            )
        } catch {
            if process.isRunning {
                process.terminate()
            }
            try? session.cleanup()
            throw error
        }
    }

    private func resolveCodexExecutable(fileManager: FileManager = .default) throws -> URL {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            throw CodexAppProcessClientError.applicationNotFound
        }

        let codexURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: false)

        guard fileManager.isExecutableFile(atPath: codexURL.path) else {
            throw CodexAppProcessClientError.applicationNotFound
        }
        return codexURL
    }

    private func executionEnvironment(
        codexURL: URL,
        isolatedSession: IsolatedCodexHomeSession
    ) -> [String: String] {
        let codexDirectory = codexURL.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let user = NSUserName()
        return [
            "CODEX_HOME": isolatedSession.rootDirectory.path,
            "HOME": home,
            "LOGNAME": user,
            "PATH": "\(codexDirectory):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": isolatedSession.tempDirectory.path,
            "USER": user
        ]
    }

    private func waitForPrompt(
        output: LockedStringBuffer,
        process: Process
    ) async throws -> IsolatedCodexLoginPrompt {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if let prompt = extractPrompt(from: output.value) {
                return prompt
            }
            if !process.isRunning {
                throw IsolatedCodexLoginError.promptUnavailable
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw IsolatedCodexLoginError.promptUnavailable
    }

    private func extractPrompt(from output: String) -> IsolatedCodexLoginPrompt? {
        let output = stripANSIEscapes(output)
        guard
            let urlRange = output.range(of: #"https://auth\.openai\.com/codex/device\S*"#, options: .regularExpression),
            let url = URL(string: String(output[urlRange])),
            let codeRange = output.range(of: #"\b[A-Z0-9]{4,}-[A-Z0-9]{4,}\b"#, options: .regularExpression)
        else {
            return nil
        }

        return IsolatedCodexLoginPrompt(url: url, userCode: String(output[codeRange]))
    }

    private func stripANSIEscapes(_ output: String) -> String {
        output.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
    }
}

private final class RunningIsolatedCodexLoginSession: IsolatedCodexLoginSession {
    let prompt: IsolatedCodexLoginPrompt
    let codexHome: URL

    private let codexURL: URL
    private let isolatedSession: IsolatedCodexHomeSession
    private let process: Process

    init(
        prompt: IsolatedCodexLoginPrompt,
        codexURL: URL,
        isolatedSession: IsolatedCodexHomeSession,
        process: Process
    ) {
        self.prompt = prompt
        self.codexURL = codexURL
        self.isolatedSession = isolatedSession
        self.process = process
        self.codexHome = isolatedSession.rootDirectory
    }

    func waitForAuthData() async throws -> Data {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: isolatedSession.authFile.path) {
                return try Data(contentsOf: isolatedSession.authFile)
            }
            if !process.isRunning {
                if FileManager.default.fileExists(atPath: isolatedSession.authFile.path) {
                    return try Data(contentsOf: isolatedSession.authFile)
                }
                throw IsolatedCodexLoginError.authCaptureFailed
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw IsolatedCodexLoginError.authCaptureTimedOut
    }

    func verifyLoginStatus() async -> Bool {
        let statusProcess = Process()
        let pipe = Pipe()
        statusProcess.executableURL = codexURL
        statusProcess.arguments = ["login", "status"]
        statusProcess.environment = [
            "CODEX_HOME": isolatedSession.rootDirectory.path,
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "\(codexURL.deletingLastPathComponent().path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": isolatedSession.tempDirectory.path
        ]
        statusProcess.standardOutput = pipe
        statusProcess.standardError = pipe

        do {
            try statusProcess.run()
            statusProcess.waitUntilExit()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return statusProcess.terminationStatus == 0 && output.contains("Logged in")
        } catch {
            return false
        }
    }

    func cancel() {
        if process.isRunning {
            process.interrupt()
        }
        if process.isRunning {
            process.terminate()
        }
    }

    func cleanup() {
        cancel()
        try? isolatedSession.cleanup()
    }
}

enum IsolatedCodexLoginError: LocalizedError {
    case promptUnavailable
    case authCaptureFailed
    case authCaptureTimedOut
    case loginStatusVerificationFailed

    var errorDescription: String? {
        switch self {
        case .promptUnavailable:
            "Codex could not start a sign-in session. Try again in a few minutes."
        case .authCaptureFailed:
            "The Codex sign-in did not complete."
        case .authCaptureTimedOut:
            "The Codex sign-in code expired before the account was added."
        case .loginStatusVerificationFailed:
            "CodexPill could not verify the signed-in account."
        }
    }
}

private final class LockedStringBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    var value: String {
        lock.withLock { storage }
    }

    func append(_ value: String) {
        lock.withLock {
            storage.append(value)
        }
    }
}
