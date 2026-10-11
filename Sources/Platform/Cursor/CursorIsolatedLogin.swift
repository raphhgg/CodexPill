import AppKit
import Foundation
import OSLog

private let cursorIsolatedLoginLogger = Logger(subsystem: "com.raphhgg.codexpill", category: "CursorIsolatedLogin")

enum CursorSignInError: Error, Equatable, Sendable {
    case notInstalled
    case launchFailed
    /// The user cancelled, so the Cursor window was closed.
    case cancelled
    case timedOut
    /// The Cursor window quit before a sign-in appeared.
    case closedBeforeSignIn
    /// CodexPill could not make its throwaway profile folder.
    case folderUnavailable
}

/// Starts and stops separate Cursor instances. Every call names its instance by PID, so the user's own Cursor is
/// never touched.
protocol CursorInstanceLaunching: Sendable {
    var isInstalled: Bool { get }
    /// Opens a new Cursor instance that keeps its profile and extensions in `profile`, and returns its PID.
    func launch(profile: URL) async throws(CursorSignInError) -> Int32
    func isRunning(_ pid: Int32) -> Bool
    /// Asks that instance to quit, and force-quits it when it is still running after a grace period.
    func terminate(_ pid: Int32) async
}

/// Cursor's own sign-in, run in a separate Cursor window with a throwaway `--user-data-dir`, so the user's Cursor
/// profile is never read or changed. CodexPill watches that profile's `state.vscdb` until the `cursorAuth/*` rows
/// appear, closes that window by its PID, copies the rows out and deletes the folder, also when the sign-in fails,
/// times out or is cancelled.
struct CursorIsolatedLogin: Sendable {
    static let timeout: Duration = .seconds(5 * 60)
    /// Cursor names its IPC socket `<user-data-dir>/<4 version chars>-main.sock`, and macOS caps a socket path at
    /// 103 bytes. With a longer profile path Cursor quits at launch without a word.
    static let socketPathSuffixLength = "/3.21-main.sock".utf8.count
    static let socketPathLimit = 103

    let launcher: any CursorInstanceLaunching
    /// Holds every throwaway profile. Every folder in it is deleted at launch.
    let root: URL
    var timeout = Self.timeout
    var pollInterval: Duration = .seconds(1)
    /// How long to wait for Cursor to fill in the email and plan rows after the access token appears.
    var settleTime: Duration = .seconds(5)
    var newFolderName: @Sendable () -> String = { String(UUID().uuidString.prefix(8)).lowercased() }

    var isInstalled: Bool {
        launcher.isInstalled
    }

    static func database(inProfile profile: URL) -> CursorStateDatabase {
        CursorStateDatabase(url: profile.appendingPathComponent("User/globalStorage/state.vscdb"))
    }

    func signIn() async throws(CursorSignInError) -> CursorSignIn {
        guard isInstalled else { throw .notInstalled }
        let profile = root.appendingPathComponent(newFolderName(), isDirectory: true)
        guard profile.path.utf8.count + Self.socketPathSuffixLength <= Self.socketPathLimit else { throw .folderUnavailable }
        do {
            try FilePermissionHardening.createPrivateDirectory(at: profile)
        } catch {
            throw .folderUnavailable
        }
        defer { try? FileManager.default.removeItem(at: profile) }

        let pid = try await launcher.launch(profile: profile)
        cursorIsolatedLoginLogger.log("Opened a sign-in Cursor window")
        let database = Self.database(inProfile: profile)
        let result = await waitForSignIn(in: database, pid: pid)
        // A cancelled sign-in must still wait for the window to quit, and a cancelled task's sleeps return at once.
        await Task { await launcher.terminate(pid) }.value
        cursorIsolatedLoginLogger.log("Closed the sign-in Cursor window")

        let signIn = try result.get()
        // Cursor flushes its last writes when it quits, so the closed database has the fullest rows.
        guard
            let final = (try? database.values(forKeys: CursorSignIn.keys)).flatMap(CursorSignIn.init(values:)),
            final.userID == signIn.userID
        else {
            return signIn
        }
        return final
    }

    /// Deletes profiles an earlier run left behind when CodexPill quit in the middle of it.
    func removeLeftovers() {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func waitForSignIn(in database: CursorStateDatabase, pid: Int32) async -> Result<CursorSignIn, CursorSignInError> {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var found: (signIn: CursorSignIn, at: ContinuousClock.Instant)?
        while true {
            // A busy or half-written database is read again on the next tick.
            if let signIn = (try? database.values(forKeys: CursorSignIn.keys)).flatMap(CursorSignIn.init(values:)) {
                let firstSeen = found?.at ?? clock.now
                found = (signIn, firstSeen)
                if signIn.email != nil || clock.now >= firstSeen.advanced(by: settleTime) {
                    return .success(signIn)
                }
            }
            let isRunning = launcher.isRunning(pid)
            let isPastDeadline = clock.now >= deadline
            if let found, !isRunning || isPastDeadline {
                return .success(found.signIn)
            }
            guard isRunning else { return .failure(.closedBeforeSignIn) }
            guard !isPastDeadline else { return .failure(.timedOut) }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return .failure(.cancelled)
            }
        }
    }
}

/// Opens Cursor.app as a new instance, the way `open -n -a Cursor --args …` does, which hands back the new
/// instance's PID. The `cursor` command starts Cursor detached and exits, leaving no PID to quit later.
struct SystemCursorInstanceLauncher: CursorInstanceLaunching {
    var quitGracePeriod: Duration = .seconds(10)

    private var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: SystemCursorAppProcessClient.bundleIdentifier)
    }

    var isInstalled: Bool {
        appURL != nil
    }

    func launch(profile: URL) async throws(CursorSignInError) -> Int32 {
        guard let appURL else { throw .notInstalled }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.arguments = Self.arguments(profile: profile)
        do {
            return try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration).processIdentifier
        } catch {
            throw .launchFailed
        }
    }

    static func arguments(profile: URL) -> [String] {
        [
            "--user-data-dir=\(profile.path)",
            "--extensions-dir=\(profile.appendingPathComponent("extensions", isDirectory: true).path)",
        ]
    }

    func isRunning(_ pid: Int32) -> Bool {
        cursorInstance(pid).map { !$0.isTerminated } ?? false
    }

    func terminate(_ pid: Int32) async {
        guard let instance = cursorInstance(pid) else { return }
        instance.terminate()
        if await waitForExit(of: instance, for: quitGracePeriod) { return }
        cursorIsolatedLoginLogger.error("The sign-in Cursor window did not quit, force-quitting it")
        instance.forceTerminate()
        _ = await waitForExit(of: instance, for: .seconds(2))
    }

    /// Only a Cursor process with this PID, so a reused PID never sends a quit to another app.
    private func cursorInstance(_ pid: Int32) -> NSRunningApplication? {
        guard let instance = NSRunningApplication(processIdentifier: pid),
              instance.bundleIdentifier == SystemCursorAppProcessClient.bundleIdentifier
        else {
            return nil
        }
        return instance
    }

    private func waitForExit(of instance: NSRunningApplication, for duration: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: duration)
        while clock.now < deadline {
            if instance.isTerminated { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return instance.isTerminated
    }
}

/// Runs a stand-in executable instead of Cursor.app, for isolated runs, which never open the real Cursor.
final class ExecutableCursorInstanceLauncher: CursorInstanceLaunching, @unchecked Sendable {
    private let executable: URL
    private let lock = NSLock()
    private var processes: [Int32: Process] = [:]

    init(executable: URL) {
        self.executable = executable
    }

    var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: executable.path)
    }

    func launch(profile: URL) async throws(CursorSignInError) -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = SystemCursorInstanceLauncher.arguments(profile: profile)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw .launchFailed
        }
        lock.withLock { processes[process.processIdentifier] = process }
        return process.processIdentifier
    }

    func isRunning(_ pid: Int32) -> Bool {
        lock.withLock { processes[pid]?.isRunning ?? false }
    }

    func terminate(_ pid: Int32) async {
        guard let process = lock.withLock({ processes.removeValue(forKey: pid) }) else { return }
        process.terminate()
        for _ in 0..<50 where process.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
