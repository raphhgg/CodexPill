import AppKit
import OSLog

private let codexAppProcessLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "SystemCodexAppProcessClient")

protocol CodexAppProcessClient {
    func assertCodexAvailable() throws
    func relaunchCodex() async throws
}

struct SystemCodexAppProcessClient: CodexAppProcessClient {
    let bundleIdentifier = "com.openai.codex"

    func assertCodexAvailable() throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil else {
            codexAppProcessLogger.error("Could not resolve Codex application URL")
            throw CodexAppProcessClientError.applicationNotFound
        }
    }

    func relaunchCodex() async throws {
        codexAppProcessLogger.log("Starting Codex relaunch flow")
        try assertCodexAvailable()
        try await terminateForRelaunch()
        codexAppProcessLogger.log("Termination phase complete, launching Codex")
        try await launchCodex()
        codexAppProcessLogger.log("Launch request returned successfully")
    }

    private func terminateRunningCodex() {
        codexAppProcessLogger.log("Requesting graceful termination for running Codex apps")
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        runningApps.forEach { $0.terminate() }
    }

    private func forceTerminateRunningCodex() {
        codexAppProcessLogger.log("Force-terminating running Codex apps")
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .forEach { $0.forceTerminate() }
    }

    private func terminateForRelaunch() async throws {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        codexAppProcessLogger.log("Found \(runningApps.count, privacy: .public) running Codex app(s) before relaunch")
        guard !runningApps.isEmpty else {
            return
        }

        terminateRunningCodex()

        if try await waitForCodexToTerminate(timeout: 0.8) {
            codexAppProcessLogger.log("Codex terminated during graceful shutdown window")
            return
        }

        forceTerminateRunningCodex()

        guard try await waitForCodexToTerminate(timeout: 4) else {
            codexAppProcessLogger.error("Codex did not terminate before relaunch timeout")
            throw CodexAppProcessClientError.relaunchTimedOut
        }
        codexAppProcessLogger.log("Codex terminated after forced shutdown")
    }

    private func launchCodex() async throws {
        try assertCodexAvailable()
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw CodexAppProcessClientError.applicationNotFound
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        codexAppProcessLogger.log("Opening Codex app at \(appURL.path, privacy: .public)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    codexAppProcessLogger.error("openApplication returned error: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                } else {
                    codexAppProcessLogger.log("openApplication completion handler returned success")
                    continuation.resume()
                }
            }
        }
    }

    private func waitForCodexToTerminate(timeout: TimeInterval) async throws -> Bool {
        codexAppProcessLogger.log("Waiting up to \(timeout, privacy: .public)s for Codex termination")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                codexAppProcessLogger.log("Detected that Codex is no longer running")
                return true
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        let terminated = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        codexAppProcessLogger.log("Termination wait finished. Terminated: \(terminated, privacy: .public)")
        return terminated
    }
}

struct ValidationCodexAppProcessClient: CodexAppProcessClient {
    func assertCodexAvailable() throws {}
    func relaunchCodex() async throws {}
}

enum CodexAppProcessClientError: LocalizedError {
    case applicationNotFound
    case relaunchTimedOut

    var errorDescription: String? {
        switch self {
        case .applicationNotFound:
            "Codex.app was not found on this Mac."
        case .relaunchTimedOut:
            "Codex did not quit in time to relaunch cleanly."
        }
    }
}
