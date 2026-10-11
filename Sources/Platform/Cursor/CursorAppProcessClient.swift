import AppKit
import OSLog

private let cursorAppProcessLogger = Logger(subsystem: "com.raphhgg.refill", category: "CursorAppProcessClient")

/// Quits and opens Cursor.app. It knows nothing about Cursor's files.
protocol CursorAppProcessClient: Sendable {
    var isRunning: Bool { get }
    /// Asks Cursor to quit and waits for it to exit. It never force-quits, so Cursor can save open work
    /// and flush its database. Throws `CursorAppProcessClientError.didNotQuit` if Cursor is still running.
    func quit() async throws
    func open() async throws
}

enum CursorAppProcessClientError: Error, Equatable {
    case applicationNotFound
    /// Cursor is still running, for example because it is asking about unsaved changes.
    case didNotQuit
}

struct SystemCursorAppProcessClient: CursorAppProcessClient {
    static let bundleIdentifier = "com.todesktop.230313mzl4w4u92"

    var quitTimeout: Duration = .seconds(15)

    var isRunning: Bool {
        !runningApps.isEmpty
    }

    func quit() async throws {
        let apps = runningApps
        guard !apps.isEmpty else { return }

        cursorAppProcessLogger.log("Asking \(apps.count, privacy: .public) Cursor app(s) to quit")
        apps.forEach { $0.terminate() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: quitTimeout)
        while clock.now < deadline {
            if runningApps.isEmpty {
                cursorAppProcessLogger.log("Cursor quit")
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard runningApps.isEmpty else {
            cursorAppProcessLogger.error("Cursor did not quit in time")
            throw CursorAppProcessClientError.didNotQuit
        }
    }

    func open() async throws {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else {
            throw CursorAppProcessClientError.applicationNotFound
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        cursorAppProcessLogger.log("Opened Cursor")
    }

    private var runningApps: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier)
    }
}

/// An isolated run's Cursor: there is none to quit or open, so a switch only rewrites the fixture database.
struct IsolatedCursorAppProcessClient: CursorAppProcessClient {
    let isRunning = false
    func quit() async throws {}
    func open() async throws {}
}
