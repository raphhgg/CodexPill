import AppKit
import Foundation

protocol CodexExecutableResolving: Sendable {
    func resolveCodexExecutable() throws -> URL
}

struct NSWorkspaceCodexExecutableResolver: CodexExecutableResolving, @unchecked Sendable {
    let bundleIdentifier = "com.openai.codex"
    var fileManager: FileManager = .default

    func resolveCodexExecutable() throws -> URL {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
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
}

struct SystemIsolatedCodexLoginClient: IsolatedCodexLoginClient {
    private let executableResolver: CodexExecutableResolving

    init(executableResolver: CodexExecutableResolving = NSWorkspaceCodexExecutableResolver()) {
        self.executableResolver = executableResolver
    }

    func startLogin() async throws -> IsolatedCodexLoginSession {
        let codexURL = try executableResolver.resolveCodexExecutable()
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
            let data = handle.availableData
            guard !data.isEmpty else { return }
            output.append(String(decoding: data, as: UTF8.self))
        }

        do {
            try process.run()
        } catch {
            try? session.cleanup()
            throw error
        }

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
                throw IsolatedCodexLoginError.promptUnavailable(reason: sanitizedFailureReason(from: output.value))
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw IsolatedCodexLoginError.promptUnavailable(reason: sanitizedFailureReason(from: output.value))
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

    private func sanitizedFailureReason(from output: String) -> String? {
        CodexLoginOutputSanitizer.sanitizedFailureReason(from: output)
    }
}

enum CodexLoginOutputSanitizer {
    static func sanitizedFailureReason(from output: String) -> String? {
        let sanitized = stripANSIEscapes(output)
            .replacingOccurrences(
                of: #"\b[A-Z0-9]{4,}-[A-Z0-9]{4,}\b"#,
                with: "[device code]",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"https://auth\.openai\.com/codex/device\S*"#,
                with: "https://auth.openai.com/codex/device",
                options: .regularExpression
            )
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !sanitized.isEmpty else {
            return nil
        }
        return String(sanitized.prefix(240))
    }

    private static func stripANSIEscapes(_ output: String) -> String {
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
