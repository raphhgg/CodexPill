import AppKit
import OSLog

private let codexAppProcessLogger = Logger(subsystem: "com.raphhgg.refill", category: "SystemCodexAppProcessClient")

enum CodexRelaunch: Equatable, Sendable {
    case relaunched
    /// No Codex app on this Mac, so nothing was quit or opened. `auth.json` changes still apply.
    case appNotFound
}

protocol CodexAppProcessClient: Sendable {
    func relaunchCodex() async throws -> CodexRelaunch
}

struct SystemCodexAppProcessClient: CodexAppProcessClient {
    let bundleIdentifier = CodexAppLocator.bundleIdentifier
    var locator = CodexAppLocator.live

    func relaunchCodex() async throws -> CodexRelaunch {
        guard let appURL = locator.appURL() else {
            codexAppProcessLogger.error("Codex app not found, skipping relaunch")
            return .appNotFound
        }
        codexAppProcessLogger.log("Starting Codex relaunch flow")
        try await terminateForRelaunch()
        codexAppProcessLogger.log("Termination phase complete, launching Codex")
        try await launchCodex(at: appURL)
        codexAppProcessLogger.log("Launch request returned successfully")
        return .relaunched
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

    private func launchCodex(at appURL: URL) async throws {
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

enum CodexAppProcessClientError: LocalizedError {
    case relaunchTimedOut

    var errorDescription: String? {
        switch self {
        case .relaunchTimedOut:
            "Codex did not quit in time to relaunch cleanly."
        }
    }
}
