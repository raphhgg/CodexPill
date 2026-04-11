import AppKit
import OSLog

private let appControllerLogger = Logger(subsystem: "com.raphhgg.codex-switchboard", category: "CodexAppController")

struct CodexAppController {
    let bundleIdentifier = "com.openai.codex"

    func relaunchCodex() async throws {
        appControllerLogger.log("Starting Codex relaunch flow")
        try await terminateForRelaunch()
        appControllerLogger.log("Termination phase complete, launching Codex")
        try await launchCodex()
        appControllerLogger.log("Launch request returned successfully")
    }

    private func terminateRunningCodex() {
        appControllerLogger.log("Requesting graceful termination for running Codex apps")
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        runningApps.forEach { $0.terminate() }
    }

    private func forceTerminateRunningCodex() {
        appControllerLogger.log("Force-terminating running Codex apps")
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .forEach { $0.forceTerminate() }
    }

    private func terminateForRelaunch() async throws {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        appControllerLogger.log("Found \(runningApps.count, privacy: .public) running Codex app(s) before relaunch")
        guard !runningApps.isEmpty else {
            return
        }

        terminateRunningCodex()

        if try await waitForCodexToTerminate(timeout: 0.8) {
            appControllerLogger.log("Codex terminated during graceful shutdown window")
            return
        }

        forceTerminateRunningCodex()

        guard try await waitForCodexToTerminate(timeout: 4) else {
            appControllerLogger.error("Codex did not terminate before relaunch timeout")
            throw CodexAppControllerError.relaunchTimedOut
        }
        appControllerLogger.log("Codex terminated after forced shutdown")
    }

    private func launchCodex() async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            appControllerLogger.error("Could not resolve Codex application URL")
            throw CodexAppControllerError.applicationNotFound
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        appControllerLogger.log("Opening Codex app at \(appURL.path, privacy: .public)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    appControllerLogger.error("openApplication returned error: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                } else {
                    appControllerLogger.log("openApplication completion handler returned success")
                    continuation.resume()
                }
            }
        }
    }

    private func waitForCodexToTerminate(timeout: TimeInterval) async throws -> Bool {
        appControllerLogger.log("Waiting up to \(timeout, privacy: .public)s for Codex termination")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                appControllerLogger.log("Detected that Codex is no longer running")
                return true
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        let terminated = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        appControllerLogger.log("Termination wait finished. Terminated: \(terminated, privacy: .public)")
        return terminated
    }
}

enum CodexAppControllerError: LocalizedError {
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
