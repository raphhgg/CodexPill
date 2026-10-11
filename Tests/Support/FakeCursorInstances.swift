import Foundation
import SQLite3

@testable import CodexPill

/// Cursor instances as far as `CursorIsolatedLogin` sees them, following what Cursor 3.21 does: an instance opened
/// with `--user-data-dir=<profile>` keeps `state.vscdb` in WAL mode under `<profile>/User/globalStorage` while it
/// runs and writes the `cursorAuth/*` rows there once the user signs in. The user's own Cursor runs as `usersPID`
/// the whole time.
final class FakeCursorInstances: CursorInstanceLaunching, @unchecked Sendable {
    enum Behavior {
        /// Signs in once the gate opens, or right away without one. `emailLater` writes the email row a moment after
        /// the token, as Cursor fills in the profile rows after storing the tokens.
        case signsIn([String: String], after: TestGate? = nil, emailLater: Bool = false)
        /// Waits for the user, who never signs in.
        case waits
        /// The user quits the window before signing in.
        case quitsBeforeSignIn
        case failsToLaunch
    }

    static let usersPID: Int32 = 100
    static let signInPID: Int32 = 4242

    private let lock = NSLock()
    private var installed = true
    private var nextBehavior: Behavior = .waits
    private var running: Set<Int32> = [usersPID]
    private var launched: [URL] = []
    private var terminated: [Int32] = []
    private var profileExistedAtQuit: [Bool] = []
    private var connection: OpaquePointer?
    private var behaviorTask: Task<Void, Never>?

    var isInstalled: Bool {
        get { lock.withLock { installed } }
        set { lock.withLock { installed = newValue } }
    }

    var behavior: Behavior {
        get { lock.withLock { nextBehavior } }
        set { lock.withLock { nextBehavior = newValue } }
    }

    var launchedProfiles: [URL] { lock.withLock { launched } }
    var terminatedPIDs: [Int32] { lock.withLock { terminated } }
    var runningPIDs: Set<Int32> { lock.withLock { running } }
    /// For each quit, whether the profile was still on disk, so CodexPill closed the window before deleting it.
    var profileWasPresentAtQuit: [Bool] { lock.withLock { profileExistedAtQuit } }

    func launch(profile: URL) async throws(CursorSignInError) -> Int32 {
        let behavior = lock.withLock {
            launched.append(profile)
            return nextBehavior
        }
        if case .failsToLaunch = behavior { throw .launchFailed }

        let database = CursorIsolatedLogin.database(inProfile: profile).url
        try? FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        lock.withLock {
            running.insert(Self.signInPID)
            connection = Self.openDatabase(at: database)
        }

        switch behavior {
        case let .signsIn(rows, gate, emailLater):
            let task = Task { [self] in
                await gate?.pass()
                var first = rows
                let email = emailLater ? first.removeValue(forKey: CursorSignIn.emailKey) : nil
                write(first)
                if let email {
                    try? await Task.sleep(for: .milliseconds(30))
                    write([CursorSignIn.emailKey: email])
                }
            }
            lock.withLock { behaviorTask = task }
        case .quitsBeforeSignIn:
            lock.withLock { quitLocked(Self.signInPID) }
        case .waits, .failsToLaunch:
            break
        }
        return Self.signInPID
    }

    func isRunning(_ pid: Int32) -> Bool {
        lock.withLock { running.contains(pid) }
    }

    func terminate(_ pid: Int32) async {
        let task = lock.withLock {
            terminated.append(pid)
            profileExistedAtQuit.append(launched.last.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
            return behaviorTask
        }
        task?.cancel()
        lock.withLock { quitLocked(pid) }
    }

    private func quitLocked(_ pid: Int32) {
        running.remove(pid)
        if pid == Self.signInPID, let connection {
            sqlite3_close_v2(connection)
            self.connection = nil
        }
    }

    private func write(_ rows: [String: String]) {
        lock.withLock {
            guard let connection else { return }
            for (key, value) in rows {
                var statement: OpaquePointer?
                sqlite3_prepare_v2(connection, "INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", -1, &statement, nil)
                sqlite3_bind_text(statement, 1, key, -1, Self.transient)
                sqlite3_bind_text(statement, 2, value, -1, Self.transient)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
        }
    }

    private static func openDatabase(at url: URL) -> OpaquePointer? {
        var connection: OpaquePointer?
        guard sqlite3_open(url.path, &connection) == SQLITE_OK else { return nil }
        sqlite3_exec(connection, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(connection, "CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)", nil, nil, nil)
        return connection
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
